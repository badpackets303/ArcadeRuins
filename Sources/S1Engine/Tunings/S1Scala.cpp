#include "S1Scala.hpp"
#include "S1TuningTable.hpp"   // s1::powerOfTwo

#include <cerrno>
#include <cmath>
#include <cstdlib>
#include <regex>

namespace s1 {

namespace {

// `components(separatedBy: .newlines)`: LF, CR and CRLF all end a line.
std::vector<std::string> lines(const std::string &text) {
    std::vector<std::string> out;
    std::string current;
    for (size_t i = 0; i < text.size(); ++i) {
        const char c = text[i];
        if (c == '\n' || c == '\r') {
            if (c == '\r' && i + 1 < text.size() && text[i + 1] == '\n') { ++i; }
            out.push_back(current);
            current.clear();
        } else {
            current.push_back(c);
        }
    }
    out.push_back(current);
    return out;
}

std::string trimmed(const std::string &s) {
    const auto space = [](unsigned char c) { return std::isspace(c) != 0; };
    size_t b = 0, e = s.size();
    while (b < e && space((unsigned char)s[b])) { ++b; }
    while (e > b && space((unsigned char)s[e - 1])) { --e; }
    return s.substr(b, e - b);
}

// Swift's `Int(string)` and `Double(string)`: the whole string, or nothing.
std::optional<long> wholeInt(const std::string &s) {
    if (s.empty()) return std::nullopt;
    char *end = nullptr;
    errno = 0;
    const long v = std::strtol(s.c_str(), &end, 10);
    if (errno != 0 || end != s.c_str() + s.size()) return std::nullopt;
    return v;
}
std::optional<double> wholeDouble(const std::string &s) {
    if (s.empty()) return std::nullopt;
    char *end = nullptr;
    errno = 0;
    const double v = std::strtod(s.c_str(), &end);
    if (errno != 0 || end != s.c_str() + s.size()) return std::nullopt;
    return v;
}

}  // namespace

std::optional<std::vector<double>> frequenciesFromScalaString(const std::string &text) {
    std::vector<double> scalaFrequencies{1.0};
    int actualFrequencyCount = 1;
    long frequencyCount = 1;
    bool parsedScala = true;
    bool parsedFirstCommentLine = false;
    bool parsedFirstNonCommentLine = false;
    bool parsedAllFrequencies = false;
    // (RATIO a/b | CENTS -a.b | -.b | -a. | -a), anchored at the start of the line
    static const std::regex regex(R"((\d+\/\d+|-?\d+\.\d+|-?\.\d+|-?\d+\.|-?\d+))");

    for (const std::string &rawLine : lines(text)) {
        const std::string lineStr = trimmed(rawLine);
        if (lineStr.empty()) continue;
        if (lineStr[0] == '!') {
            if (!parsedFirstCommentLine) { parsedFirstCommentLine = true; }
            continue;
        }
        if (!parsedFirstNonCommentLine) {
            parsedFirstNonCommentLine = true;   // the short description
            continue;
        }
        if (parsedFirstNonCommentLine && !parsedAllFrequencies) {
            if (const auto newFrequencyCount = wholeInt(lineStr)) {
                frequencyCount = *newFrequencyCount;
                if (frequencyCount == 0 || frequencyCount > 127) {
                    parsedScala = false;   // "number of notes in scala file"
                    break;
                }
                parsedAllFrequencies = true;
                continue;
            }
        }
        (void)actualFrequencyCount;   // the Swift only logs when it exceeds frequencyCount

        std::smatch match;
        if (std::regex_search(lineStr, match, regex, std::regex_constants::match_continuous)) {
            const std::string first = match.str(0);
            if (first.find('.') != std::string::npos) {
                // Cents: the Swift parses the WHOLE line, so trailing text means the line is skipped.
                if (auto scaleDegree = wholeDouble(lineStr)) {
                    if (*scaleDegree != 0) {
                        double degree = std::fabs(*scaleDegree);
                        degree /= 1200;
                        degree = s1::powerOfTwo(degree);
                        scalaFrequencies.push_back(degree);
                        ++actualFrequencyCount;
                        continue;
                    }
                }
            } else if (first.find('/') != std::string::npos) {
                if (first.find('-') != std::string::npos) {
                    parsedScala = false;   // "invalid ratio"
                    break;
                }
                const size_t slash = first.find('/');
                const long numerator = wholeInt(first.substr(0, slash)).value_or(0);
                const long denominator = wholeInt(first.substr(slash + 1)).value_or(0);
                if (denominator == 0) {
                    parsedScala = false;   // "invalid ratio"
                    break;
                }
                const double mt = double(numerator) / double(denominator);
                if (mt == 1.0 || mt == 2.0) { continue; }   // skip 1/1, 2/1
                scalaFrequencies.push_back(mt);
                ++actualFrequencyCount;
                continue;
            } else {
                if (const auto whole = wholeInt(first)) {
                    if (*whole <= 0) {
                        parsedScala = false;   // "invalid ratio"
                        break;
                    } else if (*whole == 1 || *whole == 2) {
                        continue;   // skip degrees of 1 or 2
                    } else {
                        scalaFrequencies.push_back(double(*whole));
                        ++actualFrequencyCount;
                        continue;
                    }
                }
            }
        } else {
            continue;   // "error parsing" — the line is ignored
        }
    }
    if (!parsedScala) {
        return std::nullopt;
    }
    return scalaFrequencies;
}

}  // namespace s1
