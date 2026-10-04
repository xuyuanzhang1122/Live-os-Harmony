// 平台接口替身复现 MatePad 实测的“成功但空音频profiles”能力响应，执行真实C++政策。
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),cp=require('node:child_process');
function query(configured){const dir=fs.mkdtempSync(path.join(os.tmpdir(),'t6-native-policy-'));
 const header=`#pragma once
#include <cstdint>
struct OH_AVCapability {}; struct OH_AVCodec {}; struct OH_AVFormat {}; struct OH_AVRange {int minVal;int maxVal;};
const int AV_ERR_OK=0,AVC_LEVEL_42=13,AVC_LEVEL_4=11,AVC_PROFILE_BASELINE=0,AVC_PROFILE_MAIN=8,AVC_PROFILE_HIGH=4,AAC_PROFILE_LC=0;
const char* OH_MD_KEY_PROFILE="profile"; const char* OH_MD_KEY_AUD_CHANNEL_COUNT="channels"; const char* OH_MD_KEY_AUD_SAMPLE_RATE="rate"; const char* OH_MD_KEY_AAC_IS_ADTS="adts";
OH_AVCapability* OH_AVCodec_GetCapability(const char*,bool){static OH_AVCapability c;return &c;}
bool OH_AVCapability_AreVideoSizeAndFrameRateSupported(OH_AVCapability*,int,int,int){return true;}
bool OH_AVCapability_AreProfileAndLevelSupported(OH_AVCapability*,int,int){return true;}
int OH_AVCapability_GetAudioChannelCountRange(OH_AVCapability*,OH_AVRange*r){r->minVal=1;r->maxVal=8;return 0;}
int OH_AVCapability_GetAudioSupportedSampleRates(OH_AVCapability*,const int32_t**r,uint32_t*n){static int32_t rates[]={8000,16000,32000,44100,48000};*r=rates;*n=5;return 0;}
int OH_AVCapability_GetSupportedProfiles(OH_AVCapability*,const int32_t**r,uint32_t*n){*r=nullptr;*n=0;return 0;}
OH_AVCodec* OH_AudioCodec_CreateByMime(const char*,bool){static OH_AVCodec c;return &c;}
OH_AVFormat* OH_AVFormat_Create(){static OH_AVFormat f;return &f;}
bool OH_AVFormat_SetIntValue(OH_AVFormat*,const char*,int){return true;}
int OH_AudioCodec_Configure(OH_AVCodec*,const OH_AVFormat*){return ${configured?0:-1};}
void OH_AVFormat_Destroy(OH_AVFormat*){} int OH_AudioCodec_Destroy(OH_AVCodec*){return 0;}
`;
 try{let source=fs.readFileSync(path.resolve(__dirname,'../../entry/src/main/cpp/avcap.cpp'),'utf8').split('static napi_value Query(')[0].replace(/^#include <(?:napi|multimedia)[^\n]+\n/gm,'');
 fs.writeFileSync(path.join(dir,'test.cpp'),header+'\n'+source+'\n#include <iostream>\nint main(){std::cout<<QueryCapability();}');
 cp.execFileSync('c++',['-std=c++17',path.join(dir,'test.cpp'),'-o',path.join(dir,'test')]);return JSON.parse(cp.execFileSync(path.join(dir,'test'),{encoding:'utf8'}));
 }finally{fs.rmSync(dir,{recursive:true,force:true});}}
test('MatePad empty audio profile enumeration uses explicit LC configuration confirmation',()=>assert.equal(query(true).aac,true));
test('empty profiles plus refused LC configuration remain unsupported',()=>assert.equal(query(false).aac,false));
