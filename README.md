# WIP for Mac

WIP is a local macOS app for importing client notes, browsing them by organisation or contact, and keeping a small Now / Next / Later task list.

## Install

Download `WIP-0.2.7-macOS-arm64.zip` from the repository's Releases page, unzip it, and move `WIP.app` to Applications. This build requires an Apple silicon Mac running macOS 13 or newer. The app is ad hoc signed and is not notarised; macOS may require you to control-click the app and choose Open the first time.

Your notes, organisations, contacts, and tasks are stored only on your Mac at `~/Library/Application Support/WIP/WIP.json`. They are not included in this repository or its releases.

## Build

From this folder, run `./scripts/build-app.sh`, then open `dist/WIP.app`. Xcode is not required; Apple's Swift command line tools are sufficient. The script builds for the Mac's architecture.

## Verify core behaviour

Run:

    swiftc -o .build/wip-verify Sources/WIP/Models.swift Sources/WIP/WIPStore.swift Sources/WIP/NoteDateInput.swift Sources/WIP/NoteExchange.swift scripts/verify.swift
    .build/wip-verify

    swiftc -o .build/wip-store-checks Sources/WIP/Models.swift Sources/WIP/WIPStore.swift Sources/WIP/NoteDateInput.swift Sources/WIP/NoteExchange.swift Tests/WIPStoreChecks.swift
    .build/wip-store-checks

## How WIP handles notes

An organisation name or alias on its own line starts a note section. The original pasted text and date are saved. Adding or editing an organisation, alias, or contact rechecks historical notes and can split a previously combined note or update its contact links.

Notes can be edited, deleted, searched, and merged. Merge requires notes from the same organisation. A manually edited or deleted note remains edited or deleted when names are rechecked.

Tasks are shared records. A task created from a contact view appears on an organisation view when its text mentions that organisation's name or alias. A task created from an organisation view appears on a contact view when its text mentions that contact's name. Drag tasks within or between Now, Next, and Later. Completed tasks stay grey and struck through until local midnight, then stop appearing in the active lists.
