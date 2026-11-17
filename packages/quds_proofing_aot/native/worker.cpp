// Quds' local AOT worker. No HTTP listener, shell invocation or subprocesses.
// The separately obtained AOT libraries retain their upstream LGPL notices.
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <iterator>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <vector>

#ifdef _WIN32
#include <io.h>
#include <windows.h>
#define QUDS_DUP _dup
#define QUDS_FILENO _fileno
#define QUDS_FDOPEN _fdopen
#elif defined(__APPLE__)
#include <mach-o/dyld.h>
#include <unistd.h>
#define QUDS_DUP dup
#define QUDS_FILENO fileno
#define QUDS_FDOPEN fdopen
#else
#include <unistd.h>
#define QUDS_DUP dup
#define QUDS_FILENO fileno
#define QUDS_FDOPEN fdopen
#endif

#include "nlp_base/common/rapidjson.h"
#include "nlp_base/agramtab/GerGramTab.h"
#include "nlp_base/lemmatizer_base_lib/MorphanHolder.h"
#include "synan/SynanLib/SyntaxHolder.h"
#include "www/SynanDaemon/JVisualSynAnParamBuilder.h"

namespace {
constexpr size_t kMaxRequestBytes = 256 * 1024;
constexpr size_t kMaxResponseBytes = 4 * 1024 * 1024;
constexpr size_t kMaxQueryUnits = 32768;
constexpr uint64_t kMaxId = 9007199254740991ULL;

std::filesystem::path executablePath(const char* argv0) {
#ifdef _WIN32
  std::wstring path(32768, L'\0');
  const DWORD size = GetModuleFileNameW(nullptr, path.data(), path.size());
  if (size && size < path.size()) {
    path.resize(size);
    return std::filesystem::path(path);
  }
#elif defined(__APPLE__)
  uint32_t size = 0;
  _NSGetExecutablePath(nullptr, &size);
  std::string path(size, '\0');
  if (_NSGetExecutablePath(path.data(), &size) == 0) {
    return std::filesystem::weakly_canonical(path.c_str());
  }
#else
  std::error_code error;
  auto path = std::filesystem::read_symlink("/proc/self/exe", error);
  if (!error) return path;
#endif
  return std::filesystem::absolute(argv0);
}

void setDefaultRml(const char* argv0) {
  const char* configured = std::getenv("RML");
  if (configured && *configured) return;
  const auto root = executablePath(argv0).parent_path().parent_path();
  if (!std::filesystem::is_regular_file(root / "Bin" / "rml.ini")) return;
#ifdef _WIN32
  _putenv_s("RML", root.string().c_str());
#else
  setenv("RML", root.string().c_str(), 0);
#endif
}

// Reserve the original stdout for the protocol and silence upstream diagnostics.
// They can include source words, and must never corrupt a response or leak text.
FILE* protocolOutput() {
  std::fflush(stdout);
  const int duplicate = QUDS_DUP(QUDS_FILENO(stdout));
  if (duplicate < 0) return nullptr;
  FILE* output = QUDS_FDOPEN(duplicate, "wb");
  if (!output) return nullptr;
#ifdef _WIN32
  const char* nullDevice = "NUL";
#else
  const char* nullDevice = "/dev/null";
#endif
  if (!std::freopen(nullDevice, "w", stdout) ||
      !std::freopen(nullDevice, "w", stderr)) {
    std::fclose(output);
    return nullptr;
  }
  return output;
}

bool writeResponse(FILE* output, const std::string& response) {
  return std::fwrite(response.data(), 1, response.size(), output) == response.size()
      && std::fputc('\n', output) != EOF && std::fflush(output) == 0;
}

std::string errorResponse(const std::string& id, const char* code, const char* message) {
  // Only constant messages/codes and a validated numeric id enter this JSON.
  return "{\"id\":" + id + ",\"code\":\"" + code +
      "\",\"error\":\"" + message + "\"}";
}

bool readLine(std::string& line, bool& exceeded) {
  line.clear();
  exceeded = false;
  int c;
  bool any = false;
  while ((c = std::cin.get()) != EOF) {
    any = true;
    if (c == '\n') break;
    if (line.size() < kMaxRequestBytes) line.push_back(static_cast<char>(c));
    else exceeded = true;
  }
  return any;
}

size_t utf16Units(const std::string& utf8) {
  // The complete request is already validated as UTF-8 by RapidJSON.
  size_t units = 0;
  for (unsigned char c : utf8) {
    if ((c & 0xc0) == 0x80) continue;
    units += c >= 0xf0 ? 2 : 1;
  }
  return units;
}

bool stringField(const rapidjson::Value& value, const char* name) {
  return value.HasMember(name) && value[name].IsString();
}

struct SourceBoundary {
  size_t byte;
  size_t utf16;
  uint32_t scalar;
};

class NativeSyntaxHolder : public CSyntaxHolder {
 public:
  explicit NativeSyntaxHolder(MorphLanguageEnum language) : CSyntaxHolder(language) {}
  void captureOriginalTokens(const std::string& source) {
    m_Graphan.LoadStringToGraphan(source);
    originals_ = m_Graphan.GetUnits();
  }
  const std::vector<CGraLine>& originalTokens() const { return originals_; }
 private:
  std::vector<CGraLine> originals_;
};

std::vector<SourceBoundary> sourceBoundaries(const std::string& source) {
  std::vector<SourceBoundary> positions;
  size_t units = 0;
  for (size_t byte = 0; byte < source.size();) {
    const auto lead = static_cast<unsigned char>(source[byte]);
    size_t width = lead < 0x80 ? 1 : lead < 0xe0 ? 2 : lead < 0xf0 ? 3 : 4;
    uint32_t scalar = lead & (width == 1 ? 0x7f : width == 2 ? 0x1f : width == 3 ? 0x0f : 0x07);
    for (size_t j = 1; j < width; ++j) scalar = (scalar << 6) | (static_cast<unsigned char>(source[byte + j]) & 0x3f);
    positions.push_back({byte, units, scalar});
    units += width == 4 ? 2 : 1;
    byte += width;
  }
  positions.push_back({source.size(), units, 0});
  return positions;
}

bool whitespace(uint32_t scalar) {
  return (scalar >= 9 && scalar <= 13) || scalar == 0x20 || scalar == 0x85 ||
      scalar == 0xa0 || scalar == 0x1680 || (scalar >= 0x2000 && scalar <= 0x200a) ||
      scalar == 0x2028 || scalar == 0x2029 || scalar == 0x202f || scalar == 0x205f ||
      scalar == 0x3000 || scalar == 0xfeff;
}

bool onlyWhitespace(const std::vector<SourceBoundary>& boundaries, size_t first, size_t last) {
  if (first > last || last >= boundaries.size()) return false;
  for (size_t i = first; i < last; ++i) if (!whitespace(boundaries[i].scalar)) return false;
  return true;
}

// Native words retain offsets into the graphan buffer. The pinned converter
// emits exactly one CP1251/CP1252 byte per Unicode scalar (unknowns become a
// placeholder), so map those offsets back to the untouched UTF-8/UTF-16 source.
// Every token's original graphan surface and intervening source are verified.
// This restores contiguous "zu helfen" only when both original graphan tokens
// and the engine's explicit zu-infinitive reading prove the transformation.
std::string addSourceSpans(NativeSyntaxHolder& syntax, const std::string& query,
                          MorphLanguageEnum language, const std::string& raw) {
  rapidjson::Document document;
  document.Parse(raw.data(), raw.size());
  if (document.HasParseError() || !document.IsArray() ||
      document.Size() != syntax.m_Synan.m_vectorSents.size()) return raw;
  const auto boundaries = sourceBoundaries(query);
  if (convert_from_utf8(query.c_str(), language).size() + 1 != boundaries.size()) return raw;
  const auto& graphan = syntax.originalTokens();
  std::map<int, size_t> graphanAt;
  for (size_t i = 0; i < graphan.size(); ++i) {
    if (!graphan[i].IsSpace() && graphan[i].GetTokenLength() > 0) {
      graphanAt.emplace(static_cast<int>(graphan[i].GetInputOffset()), i);
    }
  }
  size_t cursor = 0;
  bool aligned = true;
  for (size_t sentenceNo = 0; aligned && sentenceNo < document.Size(); ++sentenceNo) {
    const auto& sentence = *syntax.m_Synan.m_vectorSents[sentenceNo];
    auto& clauses = document[static_cast<rapidjson::SizeType>(sentenceNo)];
    std::vector<const CClause*> top;
    for (auto clause = sentence.m_Clauses.rbegin(); clause != sentence.m_Clauses.rend(); ++clause) {
      if (top.empty() || top.back()->m_iFirstWord == clause->m_iLastWord + 1) top.push_back(&*clause);
    }
    std::reverse(top.begin(), top.end());
    if (!clauses.IsArray() || clauses.Size() != top.size()) break;
    for (size_t clauseNo = 0; aligned && clauseNo < top.size(); ++clauseNo) {
      const CClause& clause = *top[clauseNo];
      auto& words = clauses[static_cast<rapidjson::SizeType>(clauseNo)]["words"];
      if (!words.IsArray() || words.Size() != clause.m_iLastWord - clause.m_iFirstWord + 1) {
        aligned = false;
        break;
      }
      for (size_t index = 0; aligned && index < words.Size(); ++index) {
        const auto& word = sentence.m_Words[clause.m_iFirstWord + index];
        auto& jsonWord = words[static_cast<rapidjson::SizeType>(index)];
        const auto original = graphanAt.find(word.m_GraphematicalUnitOffset);
        if (original == graphanAt.end() || !jsonWord.IsObject() ||
            !stringField(jsonWord, "str") || jsonWord["str"].GetString() != word.m_strWord) {
          aligned = false;
          break;
        }
        const auto& token = graphan[original->second];
        size_t start = token.GetInputOffset();
        const size_t end = start + token.GetTokenLength();
        if (end >= boundaries.size() || start < cursor) { aligned = false; break; }
        const std::string surface = token.GetTokenUtf8();
        if (query.substr(boundaries[start].byte, boundaries[end].byte - boundaries[start].byte) != surface) {
          aligned = false;
          break;
        }
        if (word.m_strWord != surface) {
          if (language != morphGerman || word.m_strWord != "zu-" + surface ||
              word.GetHomonymByPOSandGrammem(gVER, gZuVerbForm) == -1 || original == graphanAt.begin()) {
            aligned = false;
            break;
          }
          const auto& prefix = graphan[std::prev(original)->second];
          const size_t prefixStart = prefix.GetInputOffset();
          const size_t prefixEnd = prefixStart + prefix.GetTokenLength();
          if (prefix.GetTokenUpperUtf8() != "ZU" ||
              !onlyWhitespace(boundaries, prefixEnd, start) ||
              query.substr(boundaries[prefixStart].byte, boundaries[prefixEnd].byte - boundaries[prefixStart].byte) != prefix.GetTokenUtf8()) {
            aligned = false;
            break;
          }
          // The serializer can retain the separately marked "zu" word. In
          // that case it already owns the prefix span; this word maps only to
          // the original infinitive. Otherwise map the verified contiguous pair.
          if (prefixStart >= cursor) start = prefixStart;
          else if (prefixEnd != cursor) { aligned = false; break; }
        }
        if (!onlyWhitespace(boundaries, cursor, start)) { aligned = false; break; }
        const std::string exact = query.substr(boundaries[start].byte, boundaries[end].byte - boundaries[start].byte);
        jsonWord.AddMember("sourceStart", static_cast<uint64_t>(boundaries[start].utf16), document.GetAllocator());
        jsonWord.AddMember("sourceEnd", static_cast<uint64_t>(boundaries[end].utf16), document.GetAllocator());
        rapidjson::Value sourceText;
        sourceText.SetString(exact.data(), exact.size(), document.GetAllocator());
        jsonWord.AddMember("sourceText", sourceText, document.GetAllocator());
        cursor = end;
      }
    }
  }
  rapidjson::StringBuffer buffer;
  rapidjson::Writer<rapidjson::StringBuffer> writer(buffer);
  document.Accept(writer);
  return buffer.GetString();
}

class Engine {
 public:
  std::string execute(const std::string& action, MorphLanguageEnum language,
                      const std::string& query, bool paradigms) {
    if (!loaded_.count(language)) {
      GlobalLoadMorphHolder(language);
      loaded_.insert(language);
    }
    if (action == "morph") return GetMHolder(language).LemmatizeJson(query, paradigms);
    auto& syntax = syntax_[language];
    if (!syntax) {
      syntax = std::make_unique<NativeSyntaxHolder>(language);
      syntax->LoadSyntax();
    }
    // Upstream frees its graphan table while building morphology, so preserve
    // a deterministic original-token snapshot before that stage runs.
    syntax->captureOriginalTokens(query);
    const std::string raw = BuildJson(syntax.get(), query);
    return addSourceSpans(*syntax, query, language, raw);
  }
 private:
  std::set<MorphLanguageEnum> loaded_;
  std::map<MorphLanguageEnum, std::unique_ptr<NativeSyntaxHolder>> syntax_;
};
}  // namespace

int main(int argc, char** argv) {
  if (argc == 2 && std::string(argv[1]) == "--version") {
    std::cout << "{\"worker\":\"quds_aot_worker\",\"protocol\":1,\"aot\":\""
              << QUDS_AOT_REVISION << "\",\"nlp_base\":\""
              << QUDS_NLP_BASE_REVISION << "\"}\n";
    return 0;
  }
  if (argc == 2 && std::string(argv[1]) == "--help") {
    std::cout << "quds_aot_worker: local AOT syntax/morphology over JSON lines.\n"
                 "Read one {id,action,langua,query,withparadigms?} per stdin line.\n"
                 "Write {id,result} or {id,code,error} per stdout line.\n"
                 "RML overrides the runtime root; otherwise use ../Bin/rml.ini.\n"
                 "No network service is started. Close stdin to exit.\n";
    return 0;
  }
  if (argc != 1) return 64;
  try { setDefaultRml(argv[0]); } catch (...) { /* Report through the protocol. */ }
  FILE* output = protocolOutput();
  if (!output) return 74;
  Engine engine;
  std::string line;
  bool exceeded;
  while (readLine(line, exceeded)) {
    std::string id = "null";
    std::string response;
    bool fatal = false;
    rapidjson::Document request;
    if (exceeded) {
      response = errorResponse(id, "limit", "Native request exceeds the byte limit.");
    } else {
      request.Parse<rapidjson::kParseValidateEncodingFlag | rapidjson::kParseIterativeFlag>(
          line.data(), line.size());
      if (!request.HasParseError() && request.IsObject() &&
          request.HasMember("id") && request["id"].IsUint64() &&
          request["id"].GetUint64() <= kMaxId) {
        id = std::to_string(request["id"].GetUint64());
      }
      bool duplicate = false;
      if (request.IsObject()) {
        std::set<std::string> names;
        for (auto member = request.MemberBegin(); member != request.MemberEnd(); ++member) {
          if (!names.insert(std::string(member->name.GetString(), member->name.GetStringLength())).second) duplicate = true;
        }
      }
      if (request.HasParseError() || !request.IsObject() || duplicate || id == "null" ||
          !stringField(request, "action") || !stringField(request, "langua") ||
          !stringField(request, "query") ||
          (request.HasMember("withparadigms") && !request["withparadigms"].IsBool())) {
        response = errorResponse(id, "invalidRequest", "Invalid native request.");
      } else {
        const std::string action(request["action"].GetString(), request["action"].GetStringLength());
        const std::string languageName(request["langua"].GetString(), request["langua"].GetStringLength());
        const std::string query(request["query"].GetString(), request["query"].GetStringLength());
        const bool paradigms = request.HasMember("withparadigms") && request["withparadigms"].GetBool();
        MorphLanguageEnum language = morphUnknown;
        if (languageName == "German") language = morphGerman;
        if (languageName == "Russian") language = morphRussian;
        if (languageName == "English") language = morphEnglish;
        if (action != "syntax" && action != "morph") {
          response = errorResponse(id, "invalidRequest", "Unsupported native action.");
        } else if (language == morphUnknown || (language == morphEnglish && action == "syntax")) {
          response = errorResponse(id, "unsupportedLanguage", "Unsupported analysis language.");
        } else if (query.find('\0') != std::string::npos) {
          response = errorResponse(id, "invalidRequest", "Invalid native query.");
        } else if (utf16Units(query) > kMaxQueryUnits) {
          response = errorResponse(id, "limit", "Native query exceeds the text limit.");
        } else {
          try {
            const std::string result = engine.execute(action, language, query, paradigms);
            if (result.size() > kMaxResponseBytes - 64) {
              response = errorResponse(id, "limit", "Native result exceeds the byte limit.");
            } else {
              rapidjson::Document checked;
              checked.Parse<rapidjson::kParseValidateEncodingFlag | rapidjson::kParseIterativeFlag>(result.data(), result.size());
              if (checked.HasParseError() || (!checked.IsArray() && !checked.IsObject())) {
                response = errorResponse(id, "engineFailure", "Native analysis returned invalid data.");
                fatal = true;
              } else response = "{\"id\":" + id + ",\"result\":" + result + "}";
            }
          } catch (...) {
            response = errorResponse(id, "unavailable", "Native AOT analysis failed; verify the runtime data.");
            fatal = true;
          }
        }
      }
    }
    if (!writeResponse(output, response)) { std::fclose(output); return 74; }
    // Do not reuse possibly half-initialized upstream global state after failure.
    if (fatal) { std::fclose(output); return 2; }
  }
  std::fclose(output);
  return 0;
}
