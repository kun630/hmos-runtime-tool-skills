/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */
package ohos_app_cangjie_entry

import std.unittest.{Configuration, TestSuite, TestClass, UnitTestCase, expectEqual, TestPackage, Measurement, TimeNow}
import std.unittest.testmacro.{Test, TestCase, Expect}
import ohos.base.AppLog
import tpc.UnitTest.registerTest

@Test
class TestExample {
    @TestCase
    func test00(): Unit {
        AppLog.info("Cangjie testCase begins.");
        let a = "abc"
        let b = "b"
        @Expect(a.contains(b))
        @Expect(a, a)
    }
}

let _ = registerTest("TestExample") {TestExample()}
