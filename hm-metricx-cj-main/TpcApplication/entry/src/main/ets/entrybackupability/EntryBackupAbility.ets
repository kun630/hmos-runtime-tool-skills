/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';
import { requireCJLib } from "libark_interop_loader.so";

interface CJAbility {
  ark_BackupExtensionAbility_createCJAbility(name: string, ability: BackupExtensionAbility): number

  ark_BackupExtensionAbility_onBackup(id: number): void

  ark_BackupExtensionAbility_onBackupEx(id: number, backupInfo: string): string

  ark_BackupExtensionAbility_onRestore(id: number, bundleVersion: BundleVersion): void

  ark_BackupExtensionAbility_onRestoreEx(id: number, bundleVersion: BundleVersion, restoreInfo: string): string

  ark_BackupExtensionAbility_onProcess(id: number): string
}

let lib: CJAbility

export default class EntryBackupAbility extends BackupExtensionAbility {
  cjUIAbilityId: number = -1

  onBackup() {
    hilog.info(0x0000, 'testTag', 'onBackup ok');
    lib = requireCJLib("libtpc.CoreFileKit.backupextensionability_interop.so") as CJAbility;
    requireCJLib("libohos_app_cangjie_entry.so")
    this.cjUIAbilityId = lib.ark_BackupExtensionAbility_createCJAbility(this.context.extensionAbilityInfo.name, this);
    hilog.info(0x0000, 'testTag', 'onBackup' + this.cjUIAbilityId + this.context.extensionAbilityInfo.name);
    lib.ark_BackupExtensionAbility_onBackup(this.cjUIAbilityId);
  }

  async onBackupEx(backupInfo: string): Promise<string> {
    hilog.info(0x0000, 'testTag', 'onBackupEx ok');
    lib = requireCJLib("libtpc.CoreFileKit.backupextensionability_interop.so") as CJAbility;
    requireCJLib("libohos_app_cangjie_entry.so")
    this.cjUIAbilityId = lib.ark_BackupExtensionAbility_createCJAbility(this.context.extensionAbilityInfo.name, this);
    hilog.info(0x0000, 'testTag', 'onBackupEx' + this.cjUIAbilityId + this.context.extensionAbilityInfo.name);

    return lib.ark_BackupExtensionAbility_onBackupEx(this.cjUIAbilityId, backupInfo);
  }

  onRestore(bundleVersion: BundleVersion) {
    hilog.info(0x0000, 'testTag', 'onRestore ok %{public}s', JSON.stringify(bundleVersion));
    lib = requireCJLib("libtpc.CoreFileKit.backupextensionability_interop.so") as CJAbility;
    requireCJLib("libohos_app_cangjie_entry.so")
    this.cjUIAbilityId = lib.ark_BackupExtensionAbility_createCJAbility(this.context.extensionAbilityInfo.name, this);
    hilog.info(0x0000, 'testTag', 'onRestore' + this.cjUIAbilityId + this.context.extensionAbilityInfo.name);
    lib.ark_BackupExtensionAbility_onRestore(this.cjUIAbilityId, bundleVersion);
  }

  async onRestoreEx(bundleVersion: BundleVersion, restoreInfo: string): Promise<string> {
    hilog.info(0x0000, 'testTag', 'onRestoreEx ok');
    lib = requireCJLib("libtpc.CoreFileKit.backupextensionability_interop.so") as CJAbility;
    requireCJLib("libohos_app_cangjie_entry.so")
    this.cjUIAbilityId = lib.ark_BackupExtensionAbility_createCJAbility(this.context.extensionAbilityInfo.name, this);
    hilog.info(0x0000, 'testTag', 'onRestoreEx' + this.cjUIAbilityId + this.context.extensionAbilityInfo.name);
    return lib.ark_BackupExtensionAbility_onRestoreEx(this.cjUIAbilityId, bundleVersion, restoreInfo);
  }

  onProcess(): string {
    hilog.info(0x0000, 'testTag', 'onProcess ok');
    lib = requireCJLib("libtpc.CoreFileKit.backupextensionability_interop.so") as CJAbility;
    requireCJLib("libohos_app_cangjie_entry.so")
    this.cjUIAbilityId = lib.ark_BackupExtensionAbility_createCJAbility(this.context.extensionAbilityInfo.name, this);
    hilog.info(0x0000, 'testTag', 'onProcess' + this.cjUIAbilityId + this.context.extensionAbilityInfo.name);
    return lib.ark_BackupExtensionAbility_onProcess(this.cjUIAbilityId);
  }
}