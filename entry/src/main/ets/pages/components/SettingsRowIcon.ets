@ComponentV2
export struct SettingsRowIcon {
  @Require @Param symbol: Resource;
  @Require @Param color: ResourceColor;
  @Require @Param tileColor: ResourceColor;
  @Param dimension: number = 34;

  build() {
    Stack() {
      SymbolGlyph(this.symbol)
        .fontSize(this.dimension * 0.52)
        .fontColor([this.color])
    }
    .width(this.dimension)
    .height(this.dimension)
    .backgroundColor(this.tileColor)
    .borderRadius(this.dimension * 0.29)
  }
}
