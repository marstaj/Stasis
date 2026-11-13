/// <reference types="@raycast/api">

/* 🚧 🚧 🚧
 * This file is auto-generated from the extension's manifest.
 * Do not modify manually. Instead, update the `package.json` file.
 * 🚧 🚧 🚧 */

/* eslint-disable @typescript-eslint/ban-types */

type ExtensionPreferences = {}

/** Preferences accessible in all the extension's commands */
declare type Preferences = ExtensionPreferences

declare namespace Preferences {
  /** Preferences accessible in the `apps` command */
  export type Apps = ExtensionPreferences & {}
  /** Preferences accessible in the `pause-all` command */
  export type PauseAll = ExtensionPreferences & {}
  /** Preferences accessible in the `resume-all` command */
  export type ResumeAll = ExtensionPreferences & {}
}

declare namespace Arguments {
  /** Arguments passed to the `apps` command */
  export type Apps = {}
  /** Arguments passed to the `pause-all` command */
  export type PauseAll = {}
  /** Arguments passed to the `resume-all` command */
  export type ResumeAll = {}
}

