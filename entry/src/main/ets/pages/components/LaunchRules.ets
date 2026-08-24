export class LaunchDisplayGate {
  private consumed: boolean = false;

  consume(): boolean {
    if (this.consumed) {
      return false;
    }
    this.consumed = true;
    return true;
  }
}
