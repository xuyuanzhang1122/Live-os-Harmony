export function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(Math.max(value, minimum), maximum);
}

export function seekRangeFor(durationSeconds: number | null): number {
  if (durationSeconds === null || !Number.isFinite(durationSeconds) || durationSeconds <= 0) {
    return 90;
  }
  return clamp(durationSeconds * 0.15, 30, 300);
}

export function horizontalSeekTarget(startSeconds: number, deltaX: number, screenWidth: number,
  duration: number): number {
  if (!Number.isFinite(duration) || duration <= 0) {
    return 0;
  }
  if (!Number.isFinite(screenWidth) || screenWidth <= 0) {
    return clamp(startSeconds, 0, duration);
  }
  const target: number = startSeconds + deltaX / screenWidth * seekRangeFor(duration);
  return clamp(target, 0, duration);
}

export function shouldResume(position: number, duration: number): boolean {
  return position > 5 && position < duration - 5;
}

export function resumeTarget(position: number, duration: number): number {
  return clamp(position, 0, Math.max(0, duration - 1));
}

export function isSideZone(x: number, width: number): boolean {
  return x < width * 28 / 100 || x > width * 72 / 100;
}

export function lockPullSatisfied(startY: number, currentY: number, screenHeight: number): boolean {
  return currentY - startY >= 30 && currentY >= screenHeight * 2 / 3;
}
