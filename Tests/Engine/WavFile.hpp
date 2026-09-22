// Reads the goldens: RIFF/WAVE, 32-bit IEEE float, stereo, little-endian, as AVAudioFile wrote
// them — with JUNK and FLLR padding chunks before `data`, so the chunks are walked, not assumed.
// Bytes are assembled by hand; nothing here depends on the host's endianness or struct layout.
#ifndef S1_TEST_WAVFILE_HPP
#define S1_TEST_WAVFILE_HPP

#include <cstdint>
#include <cstring>
#include <fstream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <vector>

struct StereoRender {
    std::vector<float> left, right;
    double sampleRate = 0;
};

namespace wav {

inline uint32_t u32(const std::vector<unsigned char> &b, size_t at) {
    return uint32_t(b[at]) | uint32_t(b[at + 1]) << 8 | uint32_t(b[at + 2]) << 16 | uint32_t(b[at + 3]) << 24;
}
inline uint16_t u16(const std::vector<unsigned char> &b, size_t at) { return uint16_t(b[at] | b[at + 1] << 8); }

inline StereoRender read(const std::string &path) {
    std::ifstream file(path, std::ios::binary);
    if (!file) { throw std::runtime_error("cannot open " + path); }
    const std::vector<unsigned char> b((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    if (b.size() < 12 || std::memcmp(b.data(), "RIFF", 4) != 0 || std::memcmp(b.data() + 8, "WAVE", 4) != 0) {
        throw std::runtime_error(path + " is not a RIFF/WAVE file");
    }
    StereoRender result;
    bool haveFormat = false;
    for (size_t at = 12; at + 8 <= b.size();) {
        const uint32_t size = u32(b, at + 4);
        const size_t body = at + 8;
        if (body + size > b.size()) { break; }
        if (std::memcmp(&b[at], "fmt ", 4) == 0 && size >= 16) {
            const uint16_t format = u16(b, body), channels = u16(b, body + 2), bits = u16(b, body + 14);
            if (format != 3 || channels != 2 || bits != 32) {
                throw std::runtime_error(path + " is not 32-bit float stereo");
            }
            result.sampleRate = double(u32(b, body + 4));
            haveFormat = true;
        } else if (std::memcmp(&b[at], "data", 4) == 0) {
            if (!haveFormat) { throw std::runtime_error(path + " has data before fmt"); }
            const size_t frames = size / 8;
            result.left.resize(frames);
            result.right.resize(frames);
            for (size_t i = 0; i < frames; ++i) {
                const uint32_t l = u32(b, body + i * 8), r = u32(b, body + i * 8 + 4);
                std::memcpy(&result.left[i], &l, 4);
                std::memcpy(&result.right[i], &r, 4);
            }
            return result;
        }
        at = body + size + (size & 1);
    }
    throw std::runtime_error(path + " has no data chunk");
}

/// 32-bit float stereo, no padding chunks: for listening to, or diffing, what a harness rendered.
inline void write(const StereoRender &render, const std::string &path) {
    std::ofstream file(path, std::ios::binary);
    if (!file) { throw std::runtime_error("cannot write " + path); }
    const uint32_t frames = uint32_t(render.left.size()), dataBytes = frames * 8, rate = uint32_t(render.sampleRate);
    auto put32 = [&file](uint32_t v) { const char b[4] = {char(v), char(v >> 8), char(v >> 16), char(v >> 24)}; file.write(b, 4); };
    auto put16 = [&file](uint16_t v) { const char b[2] = {char(v), char(v >> 8)}; file.write(b, 2); };
    file.write("RIFF", 4); put32(36 + dataBytes); file.write("WAVEfmt ", 8); put32(16);
    put16(3); put16(2); put32(rate); put32(rate * 8); put16(8); put16(32);
    file.write("data", 4); put32(dataBytes);
    for (uint32_t i = 0; i < frames; ++i) {
        uint32_t l, r;
        std::memcpy(&l, &render.left[i], 4);
        std::memcpy(&r, &render.right[i], 4);
        put32(l); put32(r);
    }
}

} // namespace wav

#endif
