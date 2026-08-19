/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */
import { CJHybridComponentV2 } from '@cangjie/cjhybridview'

@Entry
@Component
struct Index {
  @State message: string = 'Hello World';
  private leakedArray: number[][] = []

  build() {
    Column() {
      Button('js leak')
        .type(ButtonType.Capsule)
        .margin({
          top: 20
        })
        .backgroundColor('#0D9FFB')
        .width('80%')
        .height('5%')
        .onClick(() => {
          for (let i = 0; i < 10000; i++) {
            this.leakedArray.push(new Array(500000).fill(1));
          }
        })
      CJHybridComponentV2({
        library: 'ohos_app_cangjie_entry',
        component: 'Index'
      })
    }
    .height('100%')
    .width('100%')
  }
}