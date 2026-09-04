// SPDX-License-Identifier: MIT
#include <AudioToolbox/AudioToolbox.h>
#include <arpa/inet.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static volatile sig_atomic_t running = 1;
static int audio_socket = -1;

static void stop_bridge(int signal_number) {
    (void)signal_number;
    running = 0;
}

static void audio_callback(void *context, AudioQueueRef queue,
                           AudioQueueBufferRef buffer,
                           const AudioTimeStamp *start_time,
                           UInt32 packet_count,
                           const AudioStreamPacketDescription *packet_descriptions) {
    (void)context;
    (void)start_time;
    (void)packet_count;
    (void)packet_descriptions;

    if (buffer->mAudioDataByteSize > 0 && audio_socket >= 0) {
        ssize_t ignored = send(audio_socket, buffer->mAudioData,
                               buffer->mAudioDataByteSize, MSG_DONTWAIT);
        (void)ignored;
    }
    if (running) {
        AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
    }
}

static void fail_osstatus(const char *operation, OSStatus status) {
    fprintf(stderr, "%s failed (OSStatus %d)\n", operation, (int)status);
    exit(1);
}

int main(int argc, char **argv) {
    const char *host = argc > 1 ? argv[1] : "127.0.0.1";
    int port = argc > 2 ? atoi(argv[2]) : 4010;
    if (port < 1 || port > 65535) {
        fprintf(stderr, "Invalid UDP port: %d\n", port);
        return 2;
    }

    audio_socket = socket(AF_INET, SOCK_DGRAM, 0);
    if (audio_socket < 0) {
        perror("socket");
        return 1;
    }

    struct sockaddr_in destination;
    memset(&destination, 0, sizeof(destination));
    destination.sin_family = AF_INET;
    destination.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, host, &destination.sin_addr) != 1) {
        fprintf(stderr, "Invalid IPv4 address: %s\n", host);
        return 2;
    }
    if (connect(audio_socket, (struct sockaddr *)&destination,
                sizeof(destination)) != 0) {
        perror("connect");
        return 1;
    }

    AudioStreamBasicDescription format;
    memset(&format, 0, sizeof(format));
    format.mSampleRate = 48000.0;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger |
                          kLinearPCMFormatFlagIsPacked;
    format.mBytesPerPacket = 4;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = 4;
    format.mChannelsPerFrame = 2;
    format.mBitsPerChannel = 16;

    AudioQueueRef queue = NULL;
    OSStatus status = AudioQueueNewInput(&format, audio_callback, NULL, NULL,
                                         kCFRunLoopCommonModes, 0, &queue);
    if (status != noErr) fail_osstatus("AudioQueueNewInput", status);

    enum { buffer_count = 4, buffer_bytes = 960 };
    for (int i = 0; i < buffer_count; ++i) {
        AudioQueueBufferRef buffer = NULL;
        status = AudioQueueAllocateBuffer(queue, buffer_bytes, &buffer);
        if (status != noErr) fail_osstatus("AudioQueueAllocateBuffer", status);
        status = AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
        if (status != noErr) fail_osstatus("AudioQueueEnqueueBuffer", status);
    }

    signal(SIGINT, stop_bridge);
    signal(SIGTERM, stop_bridge);
    status = AudioQueueStart(queue, NULL);
    if (status != noErr) fail_osstatus("AudioQueueStart", status);

    fprintf(stderr, "Streaming 48 kHz stereo s16le to udp://%s:%d\n", host, port);
    while (running) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.25, false);
    }

    AudioQueueStop(queue, true);
    AudioQueueDispose(queue, true);
    close(audio_socket);
    return 0;
}
