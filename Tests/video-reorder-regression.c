// Exercise the real RTP/FEC queue and depacketizer with deterministic packets.
// No network, encoder, or platform renderer is involved.
#include "Limelight-internal.h"

int AppVersionQuad[4] = {7, 1, 500, -1};
STREAM_CONFIGURATION StreamConfig;
CONNECTION_LISTENER_CALLBACKS ListenerCallbacks;
DECODER_RENDERER_CALLBACKS VideoCallbacks;
int NegotiatedVideoFormat = VIDEO_FORMAT_AV1_MAIN8;
bool ReferenceFrameInvalidationSupported;
volatile bool ConnectionInterrupted;

static unsigned int submittedFrames;
static unsigned int idrRequests;
static unsigned int rfiRequests;
static unsigned int spi;
static uint16_t sequence;

#define CHECK(condition) do { \
    if (!(condition)) { \
        fprintf(stderr, "FAIL %s:%d: %s (frames=%u, IDR=%u, RFI=%u)\n", \
                __FILE__, __LINE__, #condition, submittedFrames, idrRequests, rfiRequests); \
        exit(1); \
    } \
} while (0)

bool LiGetCurrentHostDisplayHdrMode(void) { return false; }
void LiRequestIdrFrame(void) { idrRequests++; }
void notifyKeyFrameReceived(void) {}
void connectionSawFrame(uint32_t frameIndex) { (void)frameIndex; }
void connectionReceivedCompleteFrame(uint32_t frameIndex) { (void)frameIndex; }
void connectionSendFrameFecStatus(PSS_FRAME_FEC_STATUS status) { (void)status; }
void connectionDetectedFrameLoss(uint32_t startFrame, uint32_t endFrame) {
    (void)startFrame;
    (void)endFrame;
    rfiRequests++;
}

static int submitDecodeUnit(PDECODE_UNIT unit) {
    CHECK(unit->fullLength > 0);
    submittedFrames++;
    return DR_OK;
}

static void startTest(PRTP_VIDEO_QUEUE queue, bool hostRfi, bool decoderRfi,
                      uint16_t firstSequence) {
    submittedFrames = idrRequests = rfiRequests = spi = 0;
    sequence = firstSequence;
    ReferenceFrameInvalidationSupported = hostRfi;
    memset(&StreamConfig, 0, sizeof(StreamConfig));
    StreamConfig.packetSize = 64;
    StreamConfig.colorSpace = COLORSPACE_REC_709;
    memset(&VideoCallbacks, 0, sizeof(VideoCallbacks));
    VideoCallbacks.capabilities = CAPABILITY_DIRECT_SUBMIT |
        (decoderRfi ? CAPABILITY_REFERENCE_FRAME_INVALIDATION_AV1 : 0);
    VideoCallbacks.submitDecodeUnit = submitDecodeUnit;
    initializeVideoDepacketizer(StreamConfig.packetSize);
    RtpvInitializeQueue(queue);
    // Model an established stream at this sequence number, including wraparound.
    queue->nextContiguousSequenceNumber = firstSequence;
}

// Each frame has three data packets with no parity. Delivering packet 2 before
// packet 1 makes the old queue speculate a loss despite all data arriving.
static void sendFrame(PRTP_VIDEO_QUEUE queue, uint32_t frameIndex, int frameType,
                      const int* order, int count) {
    for (int i = 0; i < count; i++) {
        int index = order[i];
        int size = StreamConfig.packetSize + MAX_RTP_HEADER_SIZE;
        char* buffer = calloc(1, size + sizeof(RTPV_QUEUE_ENTRY));
        CHECK(buffer != NULL);
        PRTP_PACKET packet = (PRTP_PACKET)buffer;
        packet->header = FLAG_EXTENSION;
        packet->sequenceNumber = U16(sequence + index); // Already converted by receive thread
        packet->timestamp = frameIndex * 1500;
        PNV_VIDEO_PACKET nv = (PNV_VIDEO_PACKET)(buffer + MAX_RTP_HEADER_SIZE);
        nv->frameIndex = LE32(frameIndex);
        nv->streamPacketIndex = LE32((spi + index) << 8);
        nv->flags = FLAG_CONTAINS_PIC_DATA |
            (index == 0 ? FLAG_SOF : 0) | (index == 2 ? FLAG_EOF : 0);
        nv->multiFecFlags = 0x10;
        nv->fecInfo = LE32((3U << 22) | ((uint32_t)index << 12));
        unsigned char* payload = (unsigned char*)(nv + 1);
        memset(payload, 0x55, StreamConfig.packetSize - sizeof(*nv));
        if (index == 0) {
            memset(payload, 0, 8);
            payload[0] = 1; // Eight-byte Sunshine frame header
            payload[3] = frameType;
            payload[4] = StreamConfig.packetSize - sizeof(*nv);
        }
        PRTPV_QUEUE_ENTRY entry = (PRTPV_QUEUE_ENTRY)(buffer + size);
        if (RtpvAddPacket(queue, packet, size, entry) != RTPF_RET_QUEUED) {
            free(buffer);
        }
    }
    sequence = U16(sequence + 3);
    spi += 3;
}

static void finishTest(PRTP_VIDEO_QUEUE queue) {
    RtpvCleanupQueue(queue);
    stopVideoDepacketizer();
    destroyVideoDepacketizer();
}

static void testReorderWithoutRfi(bool hostRfi, bool decoderRfi, uint16_t firstSequence) {
    RTP_VIDEO_QUEUE queue;
    const int ordered[] = {0, 1, 2};
    const int reordered[] = {0, 2, 1};
    startTest(&queue, hostRfi, decoderRfi, firstSequence);
    sendFrame(&queue, 1, 2, ordered, 3); // Seed with an IDR
    CHECK(submittedFrames == 1);
    sendFrame(&queue, 2, 1, reordered, 3);
    sendFrame(&queue, 3, 1, ordered, 3);
    CHECK(submittedFrames == 3);
    CHECK(idrRequests == 0 && rfiRequests == 0);
    finishTest(&queue);
}

static void testRealLossStillRequestsIdr(void) {
    RTP_VIDEO_QUEUE queue;
    const int ordered[] = {0, 1, 2};
    const int missingPacket[] = {0, 2};
    startTest(&queue, false, true, 100);
    sendFrame(&queue, 1, 2, ordered, 3);
    sendFrame(&queue, 2, 1, missingPacket, 2);
    sendFrame(&queue, 3, 1, ordered, 3);
    CHECK(idrRequests > 0);
    sendFrame(&queue, 4, 2, ordered, 3);
    CHECK(submittedFrames == 2);
    finishTest(&queue);
}

static void testRfiRecoveryRemainsEnabled(void) {
    RTP_VIDEO_QUEUE queue;
    const int ordered[] = {0, 1, 2};
    const int missingPacket[] = {0, 2};
    startTest(&queue, true, true, 100);
    sendFrame(&queue, 1, 2, ordered, 3);
    sendFrame(&queue, 2, 1, missingPacket, 2);
    CHECK(rfiRequests == 1 && idrRequests == 0);
    sendFrame(&queue, 3, 5, ordered, 3); // Host's post-invalidation P-frame
    CHECK(submittedFrames == 2);
    CHECK(idrRequests == 0);
    finishTest(&queue);
}

int main(void) {
    testReorderWithoutRfi(false, true, 100); // Host lacks RFI (the reported bug)
    testReorderWithoutRfi(true, false, 100); // Decoder lacks RFI
    testReorderWithoutRfi(false, false, UINT16_MAX - 3); // Sequence wraparound
    testRealLossStillRequestsIdr();
    testRfiRecoveryRemainsEnabled();
    puts("PASS: reordered packets stay playable; true loss and RFI recovery still work (5 cases)");
    return 0;
}
