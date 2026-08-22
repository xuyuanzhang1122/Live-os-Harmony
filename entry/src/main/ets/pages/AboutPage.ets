@ComponentV2
export struct AboutPage {
  private readonly notes20: string[] = [
    '备份服务器（源站）支持',
    '恢复备份自动写回配置并重启服务、双端重新同步',
    '直播间页一键导出（本地文件 + 云端短 ID）',
    '修复续播不精确',
    '长按两侧下拉锁定 2 倍速',
    '直播中标识自动刷新',
    '适配新系统设计规范'
  ];
  private readonly notes12: string[] = [
    '品牌启动动效',
    '缩略图会话缓存',
    '存储管理',
    '进度条拖动修复'
  ];
  private readonly notes11: string[] = [
    '毛玻璃主页',
    '多用户 API Key 隔离',
    '备份与进度双向同步重构',
    '全局触觉反馈'
  ];

  @Builder
  private releaseCard(version: string, notes: string[], emphasized: boolean) {
    Row({ space: 14 }) {
      Text(emphasized ? '✦' : '◆')
        .width(40)
        .height(40)
        .fontSize(20)
        .fontColor(emphasized ? Color.White : $r('app.color.brand_color'))
        .textAlign(TextAlign.Center)
        .backgroundColor(emphasized ? $r('app.color.brand_color') : '#14FF6699')
        .borderRadius(20)
        .alignSelf(ItemAlign.Start)
      Column({ space: 9 }) {
        Text(version)
          .fontSize(emphasized ? 21 : 18)
          .fontWeight(FontWeight.Bold)
          .fontColor(emphasized ? $r('app.color.brand_color') : $r('sys.color.font_primary'))
        ForEach(notes, (note: string): void => {
          Row({ space: 8 }) {
            Circle()
              .width(5)
              .height(5)
              .fill(emphasized ? $r('app.color.brand_color') : $r('sys.color.font_secondary'))
            Text(note)
              .layoutWeight(1)
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
              .lineHeight(21)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }, (note: string): string => `${version}-${note}`)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding(18)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(14)
    .shadow(emphasized ? { radius: 9, color: '#16000000', offsetY: 3 } : { radius: 0, color: Color.Transparent })
  }

  build() {
    NavDestination() {
      List({ space: 14 }) {
        ListItem() {
          Column({ space: 4 }) {
            Text('Live OS').fontSize(26).fontWeight(FontWeight.Bold)
            Text('版本 2.0.0').fontSize(14).fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .padding({ top: 12, bottom: 10 })
        }
        ListItem() {
          this.releaseCard('2.0', this.notes20, true)
        }
        ListItem() {
          this.releaseCard('1.2', this.notes12, false)
        }
        ListItem() {
          this.releaseCard('1.1', this.notes11, false)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16, bottom: 24 })
      .edgeEffect(EdgeEffect.Spring)
    }
    .title('关于')
  }
}
