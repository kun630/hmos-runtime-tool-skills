import { harTasks } from '@ohos/hvigor-ohos-plugin';
import { hvigor } from '@ohos/hvigor';
import * as fs from 'fs';
import * as path from 'path';

/**
 * ===================== 配置 =====================
 */
const INCLUDE_FEATURES: string[] = [
  'battery', 'cpu', 'crash', 'exitInfo', 'fps', 'freeze', 'laggy',
  'memLeak', 'memory', 'storage', 'thermal', 'traffic'
];

const SO_PREFIX = 'libohos_app_cangjie_hm_metricx_cj.';
const RESERVED_CANGJIE_ENTRIES = new Set(['cjpm.toml', 'index.cj', 'util']);
const ALLOWED_FEATURES = new Set([
  'battery', 'cpu', 'crash', 'exitInfo', 'fps', 'freeze', 'laggy',
  'memLeak', 'memory', 'storage', 'thermal', 'traffic'
]);

/**
 * ===================== 工具函数 =====================
 */
function safeReadDir(dir: string): string[] { try { return fs.readdirSync(dir); } catch { return []; } }
function safeRemove(target: string) { try { fs.rmSync(target, { recursive: true, force: true }); } catch {} }
function getNodeByName(root: any, name: string): any | null {
  let found: any = null;
  root.subNodes((n:any) => { if(n.getNodeName()===name) found=n; });
  return found;
}
function hookAfterRun(task: any, fn: () => void) { if(!task || typeof task.afterRun!=='function') return false; task.afterRun(fn); return true; }
function normalizeList(arr: string[]): string[] { return Array.from(new Set(arr.map(s=>s.trim()).filter(Boolean))); }
function validateIncludeFeatures(arr: string[]): string[] {
  const normalized = arr.map(item => item.trim());
  if (normalized.length === 0) {
    throw new Error('[feature-pack] INCLUDE_FEATURES cannot be empty');
  }
  const emptyIndexes = normalized
    .map((item, index) => item ? -1 : index)
    .filter(index => index >= 0);
  if (emptyIndexes.length > 0) {
    throw new Error(`[feature-pack] INCLUDE_FEATURES contains empty value(s) at index: ${emptyIndexes.join(', ')}`);
  }

  const seen = new Set<string>();
  const duplicated = new Set<string>();
  for (const item of normalized) {
    if (seen.has(item)) {
      duplicated.add(item);
      continue;
    }
    seen.add(item);
  }
  if (duplicated.size > 0) {
    throw new Error(`[feature-pack] INCLUDE_FEATURES contains duplicate value(s): ${Array.from(duplicated).join(', ')}`);
  }

  const invalid = normalized.filter(item => !ALLOWED_FEATURES.has(item));
  if (invalid.length > 0) {
    throw new Error(
      `[feature-pack] INCLUDE_FEATURES contains unsupported feature(s): ${invalid.join(', ')}. ` +
      `Allowed values: ${Array.from(ALLOWED_FEATURES).sort().join(', ')}`
    );
  }

  return normalized;
}

function isHmMetricxFeatureSo(file: string): boolean { return file.startsWith(SO_PREFIX) && file.endsWith('.so'); }
function featureNameFromSo(file: string): string | null { if(!isHmMetricxFeatureSo(file)) return null; return file.slice(SO_PREFIX.length,file.length-3); }
function isHmMetricxFeatureAsset(file: string): boolean {
  return file.startsWith(SO_PREFIX) && (file.endsWith('.so') || file.endsWith('.dll') || file.endsWith('.dylib'));
}
function featureNameFromAsset(file: string): string | null {
  if(!isHmMetricxFeatureAsset(file)) return null;
  const rest = file.slice(SO_PREFIX.length);
  const suffixes = ['.so', '.dll', '.dylib'];
  for (const suffix of suffixes) {
    if (rest.endsWith(suffix)) return rest.slice(0, rest.length - suffix.length);
  }
  return null;
}

function shouldIncludeFeature(feat: string, include: string[]): boolean {
  for (const item of include) {
    if (feat === item || feat.startsWith(item+'.')) return true;
  }
  return false;
}

/**
 * ===================== ARM64 feature so 裁剪 =====================
 */
function findArm64Dirs(modulePath: string): string[] {
  const bases = [
    path.join(modulePath,'build/default/intermediates/stripped_native_libs'),
    path.join(modulePath,'build/default/intermediates/merged_native_libs'),
    path.join(modulePath,'build/default/intermediates/native_libs'),
    path.join(modulePath,'build/default/intermediates/cmake/default/lib'),
  ];
  const out: string[] = [];
  for(const base of bases){
    if(!fs.existsSync(base)) continue;
    const level1 = safeReadDir(base);
    for(const a of level1){
      const p1 = path.join(base,a); if(!fs.existsSync(p1)) continue;
      let stat1: fs.Stats; try{ stat1=fs.statSync(p1); } catch{ continue; }
      if(!stat1.isDirectory()) continue;
      const abiDir = path.join(p1,'arm64-v8a');
      if(fs.existsSync(abiDir) && fs.statSync(abiDir).isDirectory()){ out.push(abiDir); continue; }
      const level2 = safeReadDir(p1);
      for(const b of level2){
        const p2 = path.join(p1,b); if(!fs.existsSync(p2)) continue;
        let stat2: fs.Stats; try{ stat2=fs.statSync(p2); } catch{ continue; }
        if(!stat2.isDirectory()) continue;
        const abiDir2 = path.join(p2,'arm64-v8a');
        if(fs.existsSync(abiDir2) && fs.statSync(abiDir2).isDirectory()) out.push(abiDir2);
      }
    }
  }
  return Array.from(new Set(out));
}

function cleanArm64FeatureSosByIncludeList(modulePath:string, include:string[]){
  const includeList = normalizeList(include);
  if(includeList.length===0) return;
  const arm64Dirs = findArm64Dirs(modulePath);
  if(arm64Dirs.length===0) return;
  for(const dir of arm64Dirs){
    const files = safeReadDir(dir);
    for(const f of files){
      if(!f.endsWith('.so')) continue;
      if(!isHmMetricxFeatureSo(f)) continue;
      const feat = featureNameFromSo(f); if(!feat) continue;
      if(!shouldIncludeFeature(feat, includeList)){
        safeRemove(path.join(dir,f));
        console.log(`[feature-pack] removed .so: ${f}`);
      }
    }
  }
}

/**
 * ===================== PackageHar cangjie feature 裁剪 =====================
 */
function cleanPackageHarCangjieByIncludeList(modulePath:string, include:string[]){
  const includeList = normalizeList(include);
  const candidateRoots = [
    path.join(modulePath,'build/default/cache/default/default@PackageHar/src/main/cangjie'),
    path.join(modulePath,'build/default/generated/pm/default/src/main/cangjie'),
  ];
  for (const srcRoot of candidateRoots) {
    if(!fs.existsSync(srcRoot)) continue;
    for(const entry of safeReadDir(srcRoot)){
      if(RESERVED_CANGJIE_ENTRIES.has(entry)) continue;
      const targetPath = path.join(srcRoot, entry);
      let stat: fs.Stats; try{ stat = fs.statSync(targetPath); } catch{ continue; }
      if(!stat.isDirectory()) continue;
      if(!includeList.some(item => entry===item || entry.startsWith(item+'.'))){
        safeRemove(targetPath);
        console.log(`[feature-pack] removed package dir: ${entry}`);
      }
    }
  }
}

function cleanPackageHarAssetsByIncludeList(modulePath:string, include:string[]){
  const includeList = normalizeList(include);
  const candidateRoots = [
    path.join(modulePath, 'build/default/cache/default/default@PackageHar/assets'),
  ];
  for (const assetRoot of candidateRoots) {
    if(!fs.existsSync(assetRoot)) continue;
    for (const entry of safeReadDir(assetRoot)) {
      const feat = featureNameFromAsset(entry);
      if(!feat) continue;
      if(!shouldIncludeFeature(feat, includeList)) {
        safeRemove(path.join(assetRoot, entry));
        console.log(`[feature-pack] removed asset: ${entry}`);
      }
    }
  }
}

/**
 * ===================== 主逻辑 =====================
 */
hvigor.nodesEvaluated(()=>{
  const validatedIncludeFeatures = validateIncludeFeatures(INCLUDE_FEATURES);
  const root = hvigor.getRootNode();
  const hmNode = getNodeByName(root,'hm_metricx_cj');
  if(hmNode){
    const cacheTask = hmNode.getTaskByName('default@CacheNativeLibs');
    const processHarTask = hmNode.getTaskByName('default@ProcessHarArtifacts');
    hookAfterRun(cacheTask, ()=>{
      cleanArm64FeatureSosByIncludeList(hmNode.getNodePath(), validatedIncludeFeatures);
    });
    hookAfterRun(processHarTask, ()=>{
      cleanPackageHarCangjieByIncludeList(hmNode.getNodePath(), validatedIncludeFeatures);
      cleanPackageHarAssetsByIncludeList(hmNode.getNodePath(), validatedIncludeFeatures);
    });
  }
});

export default { system: harTasks, plugins: [] };
