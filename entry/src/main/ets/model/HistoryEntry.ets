export interface WatchHistoryEntry {
  recording_id?: string;
  source_version?: string;
  id: number;
  api_key_user_id: string;
  video_path: string;
  video_name: string;
  position_seconds: number;
  duration_seconds: number;
  updated_at: string;
}

export function historyMatches(entry: WatchHistoryEntry, recordingId: string, sourceVersion: string): boolean {
  return recordingId.length > 0 && sourceVersion.length > 0 && entry.recording_id === recordingId && entry.source_version === sourceVersion;
}
