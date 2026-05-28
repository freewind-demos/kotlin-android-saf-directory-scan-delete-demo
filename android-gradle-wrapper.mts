#!/usr/bin/env bun

import { $ } from 'bun'
import { mkdtemp } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'

const PREFIX = 'android-gradle-wrapper'

const AGP_TO_GRADLE: Record<string, string> = {
  '9.2': '9.4.1', '9.1': '9.3.1', '9.0': '9.1.0',
  '8.13': '8.13', '8.12': '8.13', '8.11': '8.13', '8.10': '8.11.1', '8.9': '8.11.1',
  '8.8': '8.10.2', '8.7': '8.9', '8.6': '8.7', '8.5': '8.7', '8.4': '8.6', '8.3': '8.4',
  '8.2': '8.2', '8.1': '8.0', '8.0': '8.0',
  '7.4': '7.5', '7.3': '7.4', '7.2': '7.3.3', '7.1': '7.2', '7.0': '7.0',
  '4.2': '6.7.1', '4.1': '6.7.1', '4.0': '6.1.1',
  '3.6': '5.6.4', '3.5': '5.4.1', '3.4': '5.1.1', '3.3': '4.10.1', '3.2': '4.6', '3.1': '4.4',
}

function log(...args: unknown[]) {
  console.error(`[${PREFIX}]`, ...args)
}

function fail(message: string): never {
  console.error(`[${PREFIX}]`, message)
  process.exit(1)
}

async function rgFirst(pattern: string, files: string[]) {
  if (!files.length) return ''
  const proc = Bun.spawn(['rg', '--no-filename', '-o', '--replace', '$1', pattern, ...files], {
    stdout: 'pipe',
    stderr: 'ignore',
  })
  const text = await new Response(proc.stdout).text()
  await proc.exited
  if (proc.exitCode !== 0) return ''
  for (const line of text.split('\n')) {
    const v = line.trim()
    if (v) return v
  }
  return ''
}

async function isGradleDir(dirPath: string) {
  for (const name of ['settings.gradle.kts', 'settings.gradle', 'build.gradle.kts', 'build.gradle']) {
    if (await Bun.file(join(dirPath, name)).exists()) return true
  }
  return false
}

async function resolveAndroidDir(projectDir: string) {
  if (process.env.ANDROID_DIR?.trim()) {
    const explicit = resolve(process.env.ANDROID_DIR.trim())
    if (!(await isGradleDir(explicit))) fail(`ANDROID_DIR is not a Gradle project: ${explicit}`)
    return explicit
  }
  for (const candidate of [projectDir, join(projectDir, 'android'), join(projectDir, 'native/android')]) {
    if (await isGradleDir(candidate)) return candidate
  }
  fail(`cannot find Android Gradle dir under: ${projectDir}`)
}

async function resolveAgpVersion(androidDir: string) {
  const buildFiles: string[] = []
  for (const name of [
    'settings.gradle.kts', 'settings.gradle', 'build.gradle.kts', 'build.gradle', 'gradle/libs.versions.toml',
  ]) {
    const p = join(androidDir, name)
    if (await Bun.file(p).exists()) buildFiles.push(p)
  }
  const patterns = [
    'com\\.android\\.tools\\.build:gradle:([0-9]+\\.[0-9]+(?:\\.[0-9]+)?)',
    'id\\(["\']com\\.android\\.(?:application|library|test|dynamic-feature)["\']\\)\\s+version\\s+["\']([0-9]+\\.[0-9]+(?:\\.[0-9]+)?)["\']',
    'id\\s+["\']com\\.android\\.(?:application|library|test|dynamic-feature)["\']\\s+version\\s+["\']([0-9]+\\.[0-9]+(?:\\.[0-9]+)?)["\']',
    '^\\s*(?:agp|androidGradlePlugin)\\s*=\\s*["\']([0-9]+\\.[0-9]+(?:\\.[0-9]+)?)["\']',
  ]
  for (const pattern of patterns) {
    const matched = await rgFirst(pattern, buildFiles)
    if (matched) return matched
  }
  return ''
}

function mapGradleVersionFromAgp(agpVersion: string) {
  const parts = agpVersion.split('.')
  if (parts.length < 2) return ''
  return AGP_TO_GRADLE[`${parts[0]}.${parts[1]}`] ?? ''
}

async function resolveGradleVersion(androidDir: string) {
  if (process.env.GRADLE_VERSION?.trim()) return process.env.GRADLE_VERSION.trim()
  const agp = await resolveAgpVersion(androidDir)
  if (agp) {
    const gradle = mapGradleVersionFromAgp(agp)
    if (gradle) {
      log(`AGP ${agp} -> Gradle ${gradle}`)
      return gradle
    }
    fail(`unsupported AGP version: ${agp}; set GRADLE_VERSION manually`)
  }
  const fallback = '9.4.1'
  log(`AGP not found -> default Gradle ${fallback}`)
  return fallback
}

function requireOnPath(name: string) {
  if (!Bun.which(name)) fail(`missing command: ${name}`)
}

async function bootstrapGradle(gradleVersion: string, workspaceDir: string) {
  requireOnPath('unzip')
  requireOnPath('java')

  const distDir = join(workspaceDir, 'dist')
  const zipPath = join(workspaceDir, `gradle-${gradleVersion}-all.zip`)
  const gradleBin = join(distDir, `gradle-${gradleVersion}`, 'bin', 'gradle')

  if (await Bun.file(gradleBin).exists()) return gradleBin

  await $`mkdir -p ${distDir}`.quiet()
  const distUrl = `https://services.gradle.org/distributions/gradle-${gradleVersion}-all.zip`
  log(`download ${distUrl}`)
  const res = await fetch(distUrl)
  if (!res.ok) fail(`download failed: ${distUrl}`)
  await Bun.write(zipPath, res)

  const unzip = await $`unzip -q ${zipPath} -d ${distDir}`.nothrow()
  if (unzip.exitCode !== 0) fail(`unzip failed: ${zipPath}`)
  if (!(await Bun.file(gradleBin).exists())) fail(`gradle bin missing after unzip: ${gradleBin}`)
  return gradleBin
}

async function copyWrapperFiles(sourceDir: string, targetDir: string) {
  const files = ['gradlew', 'gradlew.bat', 'gradle/wrapper/gradle-wrapper.jar', 'gradle/wrapper/gradle-wrapper.properties']
  for (const rel of files) {
    const src = join(sourceDir, rel)
    const dst = join(targetDir, rel)
    if (!(await Bun.file(src).exists())) fail(`missing generated wrapper file: ${src}`)
    await $`mkdir -p ${dirname(dst)}`.quiet()
    await Bun.write(dst, Bun.file(src))
  }
  await $`chmod +x ${join(targetDir, 'gradlew')}`.quiet()
}

async function generateWrapper(androidDir: string, gradleVersion: string, workspaceDir: string) {
  const bootstrapDir = join(workspaceDir, 'bootstrap')
  await $`mkdir -p ${bootstrapDir}`.quiet()
  await Bun.write(join(bootstrapDir, 'settings.gradle.kts'), 'rootProject.name = "wrapper-bootstrap"\n')
  await Bun.write(join(bootstrapDir, 'build.gradle.kts'), '\n')

  const gradleBin = await bootstrapGradle(gradleVersion, workspaceDir)
  log(`generate wrapper via Gradle ${gradleVersion}`)

  const proc = Bun.spawn(
    [gradleBin, 'wrapper', '--gradle-version', gradleVersion, '--distribution-type', 'all'],
    { cwd: bootstrapDir, stdout: 'ignore', stderr: 'ignore' },
  )
  await proc.exited
  if (proc.exitCode !== 0) fail(`wrapper task failed for Gradle ${gradleVersion}`)
  await copyWrapperFiles(bootstrapDir, androidDir)
}

const projectDir = resolve(process.env.PROJECT_DIR?.trim() || process.cwd())
const androidDir = await resolveAndroidDir(projectDir)
const gradleVersion = await resolveGradleVersion(androidDir)
const workspaceDir = await mkdtemp(join(tmpdir(), 'android-gradle-wrapper.'))

try {
  await generateWrapper(androidDir, gradleVersion, workspaceDir)
} finally {
  await $`rm -rf ${workspaceDir}`.quiet()
}

log('done')
log(`android_dir: ${androidDir}`)
log(`gradle_version: ${gradleVersion}`)
log(`wrapper: ${join(androidDir, 'gradlew')}`)
