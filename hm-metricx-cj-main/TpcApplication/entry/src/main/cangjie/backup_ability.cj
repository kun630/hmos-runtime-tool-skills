/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */
package ohos_app_cangjie_entry

import ohos.base.AppLog
import tpc.CoreFileKit.BackupExtensionAbility.BundleVersion
import tpc.CoreFileKit.BackupExtensionAbility.BackupExtensionAbility

let ENTRYBACKUPABILITY_REGISTER_RESULT = BackupExtensionAbility.registerCreator("EntryBackupAbility", {=> EntryBackupAbility()})

class EntryBackupAbility <: BackupExtensionAbility {
    public override func onBackup(): Unit {
        AppLog.info("BackupAbility onBackup.")
    }

    public override func onBackupEx(backupInfo: String): String {
        AppLog.info("BackupAbility onBackupEx. backupinfo: ${backupInfo}")
        return ''
    }

    public override func onRestore(bundleVersion: BundleVersion): Unit {
        AppLog.info("BackupAbility onRestore. version name: ${bundleVersion.name} version code ${bundleVersion.code}")
    }

    public override func onRestoreEx(bundleVersion: BundleVersion, restoreInfo: String): String {
        AppLog.info("BackupAbility onRestoreEx. version name ${bundleVersion.name} restoreinfo ${restoreInfo}")
        return ''
    }

    public override func onProcess(): String {
        AppLog.info("BackupAbility onProcess.")
        return ''
    }
}
