import { describe, expect, it } from '@ohos/hypium';
import { VideoRoomInfo } from '../main/ets/model/VideoLibrary';
import { videoLibraryRoomKey, videoLibrarySizeText } from '../main/ets/viewmodel/VideoLibraryViewModel';

function statisticsRoom(): VideoRoomInfo {
  return new VideoRoomInfo({
    host_name: '主播', platform: '抖音', folder_path: '抖音/主播', video_count: 1,
    total_size: 188978561024, latest_video_at: 1, latest_video: 'a.flv', recording: false, url: null
  });
}

export default function videoLibraryStatisticsTest(): void {
  describe('VideoLibraryStatistics', (): void => {
    it('直接展示服务端核验文本', 0, (): void => {
      const room = statisticsRoom();
      room.total_size = 176;
      room.total_size_text = '189.0 GB';
      room.statistics_status = 'verified';
      expect(videoLibrarySizeText(room)).assertEqual('189.0 GB');
    });
    it('旧服务端字节值使用统一十进制单位', 0, (): void => {
      expect(videoLibrarySizeText(statisticsRoom())).assertEqual('189.0 GB');
    });
    it('核验失败时不能显示旧数字', 0, (): void => {
      const room = statisticsRoom();
      room.statistics_status = 'unavailable';
      room.total_size_text = '176 GB';
      expect(videoLibrarySizeText(room)).assertEqual('统计暂不可用');
    });
    it('大小变化会使同一房间的卡片重新绘制', 0, (): void => {
      const room = statisticsRoom();
      const before = videoLibraryRoomKey(room);
      room.total_size = 200000000000;
      expect(videoLibraryRoomKey(room) === before).assertFalse();
    });
    it('数量封面和直播状态变化会更新卡片键', 0, (): void => {
      const room = statisticsRoom();
      let before = videoLibraryRoomKey(room);
      room.video_count = 2;
      expect(videoLibraryRoomKey(room) === before).assertFalse();
      before = videoLibraryRoomKey(room);
      room.latest_video = 'b.flv';
      expect(videoLibraryRoomKey(room) === before).assertFalse();
      before = videoLibraryRoomKey(room);
      room.recording = true;
      expect(videoLibraryRoomKey(room) === before).assertFalse();
    });
  });
}
