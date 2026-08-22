@ComponentV2
export struct RestoreBackupPage {
  build() {
    NavDestination() {
      Column({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.archivebox'))
          .fontSize(48)
          .fontColor([$r('app.color.brand_color')])
        Text('恢复备份将在 TASK-7 实现')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .padding(24)
    }
    .title('恢复备份')
  }
}
