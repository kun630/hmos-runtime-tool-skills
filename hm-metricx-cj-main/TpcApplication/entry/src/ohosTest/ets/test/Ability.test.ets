/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { requireCJLib } from 'libark_interop_loader.so';

interface Lib {
  TestExample: () => Promise<void>;
}

export default function abilityTest() {
  describe('ActsAbilityTest', () => {
    const lib = requireCJLib('libohos_app_cangjie_entry.so') as Lib;
    beforeAll(() => {
    })
    beforeEach(() => {
    })
    afterEach(() => {
    })
    afterAll(() => {
    })
    it('TestExample', 0, async () => {
      await lib.TestExample();
    })
  })
}