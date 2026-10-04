#include <napi/native_api.h>
#include <multimedia/player_framework/native_avcapability.h>
#include <multimedia/player_framework/native_avcodec_base.h>
#include <multimedia/player_framework/native_avcodec_audiocodec.h>
#include <multimedia/player_framework/native_avformat.h>
#include <algorithm>
#include <sstream>
#include <string>

// 一些实际设备对 AAC profiles 返回成功但空数组；明确配置 LC/48kHz/双声道验证，失败不猜能力。
static bool ConfirmAacLC()
{
    OH_AVCodec *codec = OH_AudioCodec_CreateByMime("audio/mp4a-latm", false);
    OH_AVFormat *format = OH_AVFormat_Create();
    bool supported = false;
    if (codec && format) {
        OH_AVFormat_SetIntValue(format, OH_MD_KEY_PROFILE, AAC_PROFILE_LC);
        OH_AVFormat_SetIntValue(format, OH_MD_KEY_AUD_CHANNEL_COUNT, 2);
        OH_AVFormat_SetIntValue(format, OH_MD_KEY_AUD_SAMPLE_RATE, 48000);
        OH_AVFormat_SetIntValue(format, OH_MD_KEY_AAC_IS_ADTS, 1);
        supported = OH_AudioCodec_Configure(codec, format) == AV_ERR_OK;
    }
    if (format) OH_AVFormat_Destroy(format);
    if (codec) OH_AudioCodec_Destroy(codec);
    return supported;
}

// API 10 能力查询，API 12 可用；限制到实际验证的 H264 8-bit SDR/AAC-LC 基线。
static std::string QueryCapability()
{
    OH_AVCapability *video = OH_AVCodec_GetCapability("video/avc", false);
    OH_AVCapability *audio = OH_AVCodec_GetCapability("audio/mp4a-latm", false);
    const bool size60 = video && OH_AVCapability_AreVideoSizeAndFrameRateSupported(video, 1920, 1080, 60);
    const bool size30 = video && OH_AVCapability_AreVideoSizeAndFrameRateSupported(video, 1920, 1080, 30);
    const int32_t level = size60 ? AVC_LEVEL_42 : AVC_LEVEL_4;
    const int32_t profiles[] = {AVC_PROFILE_BASELINE, AVC_PROFILE_MAIN, AVC_PROFILE_HIGH};
    const char *names[] = {"baseline", "main", "high"};
    std::ostringstream out;
    out << "{\"profiles\":[";
    bool first = true;
    if (size60 || size30) {
        for (int i = 0; i < 3; ++i) {
            if (OH_AVCapability_AreProfileAndLevelSupported(video, profiles[i], level)) {
                if (!first) out << ',';
                out << '"' << names[i] << '"';
                first = false;
            }
        }
    }
    bool aac = false;
    const int32_t *rates = nullptr, *audioProfiles = nullptr;
    uint32_t rateCount = 0, profileCount = 0;
    OH_AVRange channels{};
    const int channelStatus = audio ? OH_AVCapability_GetAudioChannelCountRange(audio, &channels) : -1;
    const int ratesStatus = audio ? OH_AVCapability_GetAudioSupportedSampleRates(audio, &rates, &rateCount) : -1;
    const int profilesStatus = audio ? OH_AVCapability_GetSupportedProfiles(audio, &audioProfiles, &profileCount) : -1;
    if (audio && channelStatus == AV_ERR_OK && channels.minVal <= 1 && channels.maxVal >= 2 &&
        ratesStatus == AV_ERR_OK && rates && profilesStatus == AV_ERR_OK) {
        aac = profileCount == 0 ? ConfirmAacLC() :
            audioProfiles && std::find(audioProfiles, audioProfiles + profileCount, AAC_PROFILE_LC) != audioProfiles + profileCount;
        for (int32_t rate : {8000, 16000, 32000, 44100, 48000}) {
            aac = aac && std::find(rates, rates + rateCount, rate) != rates + rateCount;
        }
    }
    out << "],\"fps\":" << (size60 ? 60 : 30) << ",\"level\":" << (size60 ? 42 : 40)
        << ",\"aac\":" << (aac ? "true" : "false")
        << ",\"audio_channels\":[" << channels.minVal << ',' << channels.maxVal << "]"
        << ",\"audio_query_status\":[" << channelStatus << ',' << ratesStatus << ',' << profilesStatus << ']'
        << ",\"audio_rates\":[";
    for (uint32_t i = 0; rates && i < rateCount; ++i) { if (i) out << ','; out << rates[i]; }
    out << "],\"audio_profiles\":[";
    for (uint32_t i = 0; audioProfiles && i < profileCount; ++i) { if (i) out << ','; out << audioProfiles[i]; }
    out << "]}";
    return out.str();
}

static napi_value Query(napi_env env, napi_callback_info info)
{
    const std::string result = QueryCapability();
    napi_value value;
    napi_create_string_utf8(env, result.c_str(), result.size(), &value);
    return value;
}
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {{"query", nullptr, Query, nullptr, nullptr, nullptr, napi_default, nullptr}};
    napi_define_properties(env, exports, 1, desc);
    return exports;
}
static napi_module module = {1, 0, nullptr, Init, "avcap", nullptr, {0}};
extern "C" __attribute__((constructor)) void RegisterCapability() { napi_module_register(&module); }
