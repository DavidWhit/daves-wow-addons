"""Self-test for the Python kit scripts.

Runs Test-WowAddon.py, New-WowAddon.py, Link-WowAddons.py, Find-WowApi.py, and Prepare-WowReview.py.
The fake WoW install stays in a temp folder. Junctions are removed before the temp tree is.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(ROOT, "scripts")
sys.path.insert(0, SCRIPTS)
import wowkit

PASSED = 0
FAILED = 0


def host(message=""):
    print(message, flush=True)


def assert_that(cond, what):
    global PASSED, FAILED
    if cond:
        PASSED += 1
        host(f"  PASS  {what}")
    else:
        FAILED += 1
        host(f"  FAIL  {what}")


def run(args):
    return subprocess.run([sys.executable, *args], capture_output=True, text=True)


def invoke_check(path, flavors=("forever",)):
    proc = run([os.path.join(SCRIPTS, "Test-WowAddon.py"), "-Path", path, "-Flavor", ",".join(flavors), "-Json"])
    try:
        result = json.loads(proc.stdout)
    except json.JSONDecodeError:
        result = None
    return proc.returncode, result


def has(result, rule, sev, line=0):
    if not result:
        return False
    for item in result.get("Findings") or []:
        if item["Rule"] == rule and item["Severity"] == sev and (line == 0 or item["Line"] == line):
            return True
    return False


def last_json(text):
    for line in reversed(text.splitlines()):
        stripped = line.strip()
        if stripped.startswith("[") or stripped.startswith("{"):
            return json.loads(stripped)
    return None


def append_ascii(path, line):
    with open(path, "a", encoding="ascii", newline="") as handle:
        handle.write(line + "\r\n")


def unlink_dir(folder):
    if not os.path.isdir(folder):
        return
    for name in os.listdir(folder):
        full = os.path.join(folder, name)
        if wowkit.is_link(full):
            wowkit.remove_link(full)


def status_of(rows, client, addon):
    hits = [row for row in rows if row.get("Client") == client and row.get("Addon") == addon]
    if len(hits) != 1:
        return None
    return hits[0].get("Status")


def main(argv):
    global PASSED, FAILED
    keep = any(token.lower() in ("-keeptemp", "--keeptemp") for token in argv)
    temp_base = os.environ["TEMP"]
    for idx, tok in enumerate(argv):
        if tok.lower() in ("-tempdir", "--tempdir") and idx + 1 < len(argv):
            temp_base = argv[idx + 1]
    here = os.path.dirname(os.path.abspath(__file__))

    host("Broken fixture (forever):")
    code, result = invoke_check(os.path.join(here, "fixtures", "BrokenAddon"))
    assert_that(code == 1, "exit code 1 when errors exist")
    assert_that(has(result, "toc-missing-file", "error"), "missing TOC file")
    assert_that(has(result, "toc-interface", "warn"), "Interface missing 16001")
    assert_that(has(result, "file-case", "warn"), "file name case mismatch")
    assert_that(has(result, "toc-directive", "info"), "unknown TOC directive")
    assert_that(has(result, "savedvariables-unused", "warn"), "unused SavedVariables")
    assert_that(has(result, "unloaded-file", "warn"), "Lua file not in TOC")
    assert_that(has(result, "cleu-removed", "error", 6), "COMBAT_LOG_EVENT_UNFILTERED on Forever")
    assert_that(has(result, "unknown-event", "error", 7), "unknown event")
    assert_that(has(result, "moved-api", "warn", 10), "GetSpellInfo -> C_Spell")
    assert_that(has(result, "unknown-global", "warn", 11), "UnitAura does not exist on Forever")
    assert_that(has(result, "deprecated-api", "warn", 12), "deprecation shim call")
    assert_that(has(result, "unknown-namespace", "error", 13), "unknown C_ namespace")
    assert_that(has(result, "unknown-function", "warn", 14), "unknown C_ function")
    assert_that(has(result, "secret-value", "warn", 17), "secret compared")
    assert_that(has(result, "secret-value", "warn", 18), "secret concatenated")
    assert_that(has(result, "slash-handler", "error"), "slash command without handler")
    assert_that(not has(result, "moved-api", "warn", 5), "no false positive on CreateFrame")
    luacheck = shutil.which("luacheck") or os.path.isfile(
        os.path.join(os.environ.get("LOCALAPPDATA", ""), "wow-addon-kit", "bin", "luacheck.exe")
    )
    if luacheck:
        assert_that(has(result, "luacheck-W111", "warn"), "accidental global (luacheck)")
        assert_that(has(result, "luacheck-E011", "error"), "syntax error (luacheck)")
    else:
        host("  SKIP  luacheck checks (run scripts\\Install-WowDevTools.py)")

    host("Edit Mode fixture (own settings window, no shared dialog):")
    _code, edit = invoke_check(os.path.join(here, "fixtures", "EditModeNoKit"))
    assert_that(has(edit, "editmode-dialog", "error"), "Edit Mode addon without EditModeDialog.lua")
    assert_that(has(edit, "editmode-ui", "error", 5), "hand-built DefaultPanelTemplate window")
    assert_that(has(edit, "editmode-ui", "error", 6), "hand-built MinimalSliderWithSteppers slider")
    assert_that(has(edit, "editmode-ui", "error", 7), "hand-built UICheckButtonTemplate checkbox")
    assert_that(not has(edit, "editmode-ui", "error", 8), "'-- editmode-ui: ok' marks a window that isn't Edit Mode settings")
    assert_that(not has(edit, "editmode-ui", "error", 12), "a template named only in a trailing comment is ignored")
    assert_that(has(edit, "editmode-snap", "error", 14), "hand-rolled grid snapping")
    assert_that(has(edit, "editmode-snap", "warn"), "own dragging without the kit's SnapRect")

    host("Invoked the way the skills do (py script, comma-separated flavors):")
    proc = run([
        os.path.join(SCRIPTS, "Test-WowAddon.py"),
        "-Path", os.path.join(here, "fixtures", "BrokenAddon"),
        "-Flavor", "forever,retail",
        "-Json",
    ])
    try:
        via_file = json.loads(proc.stdout)
    except json.JSONDecodeError:
        via_file = None
    assert_that(via_file is not None and proc.returncode == 1, "runs as a script and returns exit 1 for errors")
    assert_that(via_file is not None and len(via_file.get("Flavors") or []) == 2, "comma-separated -Flavor parsed into two flavors")

    host("Scaffold (forever, retail, classic_era):")
    tmp = os.path.join(temp_base, "wowkit-selftest-" + uuid.uuid4().hex[:8])
    os.makedirs(tmp)
    try:
        run([
            os.path.join(SCRIPTS, "New-WowAddon.py"),
            "-Name", "KitProbe", "-OutDir", tmp,
            "-Flavor", "forever,retail,classic_era",
            "-Author", "selftest", "-Icon", "INV_Misc_Gear_01",
        ])
        probe = os.path.join(tmp, "KitProbe")
        toc_path = os.path.join(probe, "KitProbe.toc")
        assert_that(os.path.isfile(toc_path), "TOC named after the folder")
        toc = open(toc_path, "r", encoding="utf-8").read()
        assert_that(re.search(r"## Interface: 16001\b", toc) is not None, "Forever Interface 16001 first")
        assert_that("{{" not in toc, "no unreplaced template tokens")
        blob = open(toc_path, "rb").read()
        assert_that(not (blob[:1] == b"\xef" and blob[1:2] == b"\xbb"), "TOC written without BOM")
        code, checked = invoke_check(probe, ("forever", "retail", "classic_era"))
        errors = checked["Errors"] if checked else "?"
        warns = checked["Warnings"] if checked else "?"
        assert_that(
            code == 0 and checked and checked["Errors"] == 0 and checked["Warnings"] == 0,
            f"scaffold is clean ({errors} errors, {warns} warnings)",
        )

        core = os.path.join(probe, "Core.lua")
        append_ascii(core, '-- Edit Mode: EventRegistry "EditMode.Enter" could show something here')
        commented = invoke_check(probe)[1]
        assert_that(
            not has(commented, "editmode-dialog", "warn") and not has(commented, "editmode-dialog", "error"),
            "Edit Mode mentioned only in a comment is ignored",
        )
        append_ascii(core, 'EventRegistry:RegisterCallback("EditMode.Enter", function() end, ns)')
        code, checked = invoke_check(probe)
        assert_that(
            has(checked, "editmode-dialog", "warn") and code == 0,
            "Edit Mode listener with no settings: warning, not an error",
        )

        run([
            os.path.join(SCRIPTS, "New-WowAddon.py"),
            "-Name", "KitEdit", "-OutDir", tmp,
            "-Author", "selftest", "-Icon", "INV_Misc_Gear_01", "-EditMode",
        ])
        edit_dir = os.path.join(tmp, "KitEdit")
        edit_toc = open(os.path.join(edit_dir, "KitEdit.toc"), "r", encoding="utf-8").read()
        assert_that(
            re.search(r"(?m)^Core\.lua\r?\nEditModeDialog\.lua\r?\nEditMode\.lua", edit_toc) is not None,
            "-EditMode lists EditModeDialog.lua and EditMode.lua after Core.lua",
        )
        edit_lua = open(os.path.join(edit_dir, "EditMode.lua"), "r", encoding="utf-8").read()
        assert_that(
            "ns.EditMode.Attach" in edit_lua and "{{" not in edit_lua,
            "-EditMode adds EditMode.lua wired through ns.EditMode.Attach",
        )
        append_ascii(os.path.join(edit_dir, "Core.lua"), 'EventRegistry:RegisterCallback("EditMode.Enter", function() end, ns)')
        code, checked = invoke_check(edit_dir)
        errors = checked["Errors"] if checked else "?"
        warns = checked["Warnings"] if checked else "?"
        assert_that(
            code == 0 and checked and checked["Errors"] == 0 and checked["Warnings"] == 0,
            f"-EditMode scaffold that joins Edit Mode is clean ({errors} errors, {warns} warnings)",
        )
        append_ascii(os.path.join(edit_dir, "EditModeDialog.lua"), "-- local change")
        assert_that(has(invoke_check(edit_dir)[1], "editmode-dialog", "warn"), "edited copy of EditModeDialog.lua flagged")
    finally:
        if not keep:
            shutil.rmtree(tmp, ignore_errors=True)
        else:
            host(f"  kept {tmp}")

    host("Link-WowAddons (fake WoW install in a temp folder):")
    tmp = os.path.join(temp_base, "wowkit-linktest-" + uuid.uuid4().hex[:8])
    wow = os.path.join(tmp, "World of Warcraft")
    src = os.path.join(tmp, "wowaddons")
    elsewhere = os.path.join(tmp, "elsewhere")
    forever_addons = os.path.join(wow, "_classic_beta_", "Interface", "AddOns")
    retail_addons = os.path.join(wow, "_retail_", "Interface", "AddOns")
    link = os.path.join(SCRIPTS, "Link-WowAddons.py")
    try:
        for folder in (
            forever_addons, retail_addons, elsewhere,
            os.path.join(src, "ForeverOnly"), os.path.join(src, "Both"),
            os.path.join(src, "RetailOnly"), os.path.join(src, "NotAnAddon"),
            os.path.join(forever_addons, "Both"),
        ):
            os.makedirs(folder, exist_ok=True)
        with open(os.path.join(wow, ".build.info"), "w", encoding="utf-8", newline="") as handle:
            handle.write(
                "Branch!STRING:0|Active!DEC:1|Version!STRING:0|Product!STRING:0\n"
                "us|1|1.60.1.70205|wow_classic_beta\n"
                "us|1|12.1.0.65000|wow\n"
            )
        with open(os.path.join(wow, "_classic_beta_", ".flavor.info"), "w", encoding="utf-8", newline="") as handle:
            handle.write("Product Flavor!STRING:0\nwow_classic_beta\n")
        with open(os.path.join(src, "ForeverOnly", "ForeverOnly.toc"), "w", encoding="utf-8", newline="") as handle:
            handle.write("## Interface: 16001\n")
        with open(os.path.join(src, "Both", "Both.toc"), "w", encoding="utf-8", newline="") as handle:
            handle.write("## Interface: 16001, 120100\n")
        with open(os.path.join(src, "RetailOnly", "RetailOnly_Mainline.toc"), "w", encoding="utf-8", newline="") as handle:
            handle.write("## Interface: 120100\n")
        with open(os.path.join(src, "NotAnAddon", "README.md"), "w", encoding="utf-8", newline="") as handle:
            handle.write("no toc here\n")
        with open(os.path.join(forever_addons, "Both", "marker.txt"), "w", encoding="utf-8", newline="") as handle:
            handle.write("installed copy\n")
        wowkit.new_link(os.path.join(retail_addons, "RetailOnly"), elsewhere)

        installs = wowkit.wow_install(wow)
        assert_that(
            any(client.Folder == "_retail_" and client.Flavor == "retail" for client in installs),
            "client without .flavor.info identified by folder name",
        )

        what_if = run([link, "-Path", src, "-Root", wow, "-WhatIf"])
        assert_that(
            os.path.isfile(os.path.join(forever_addons, "Both", "marker.txt"))
            and not os.path.exists(os.path.join(forever_addons, "ForeverOnly")),
            "-WhatIf changes nothing",
        )
        if what_if.returncode != 0:
            host(what_if.stderr)

        linked = run([link, "-Path", src, "-Root", wow, "-PassThru"])
        rows = last_json(linked.stdout) or []
        assert_that(not any(row.get("Addon") == "NotAnAddon" for row in rows), "folder without a TOC ignored")
        assert_that(
            status_of(rows, "_classic_beta_", "ForeverOnly") == "Linked"
            and wowkit.same_path(wowkit.link_target(os.path.join(forever_addons, "ForeverOnly")), os.path.join(src, "ForeverOnly")),
            "new addon linked",
        )
        assert_that(
            status_of(rows, "_retail_", "ForeverOnly") == "Skipped"
            and not os.path.exists(os.path.join(retail_addons, "ForeverOnly")),
            "Forever-only addon not linked into Retail",
        )
        assert_that(
            status_of(rows, "_classic_beta_", "RetailOnly") == "Skipped",
            "flavor TOC (_Mainline) read: Retail-only addon not linked into Forever",
        )
        assert_that(
            status_of(rows, "_retail_", "RetailOnly") == "Relinked"
            and wowkit.same_path(wowkit.link_target(os.path.join(retail_addons, "RetailOnly")), os.path.join(src, "RetailOnly"))
            and os.path.isdir(elsewhere),
            "stale link re-pointed, old target kept",
        )
        backup_root = os.path.join(wow, "_classic_beta_", "Interface", "AddOns.backup")
        backups = []
        if os.path.isdir(backup_root):
            backups = [name for name in os.listdir(backup_root) if name.startswith("Both-")]
        both_linked = wowkit.is_link(os.path.join(forever_addons, "Both"))
        marker_kept = bool(backups) and os.path.isfile(os.path.join(backup_root, backups[0], "marker.txt"))
        assert_that(
            both_linked and len(backups) == 1 and marker_kept,
            "real folder moved to AddOns.backup, then linked",
        )
        recorder = os.path.join(forever_addons, "!WowKitErrors", "!WowKitErrors.toc")
        assert_that(
            status_of(rows, "_classic_beta_", "!WowKitErrors") == "Linked"
            and status_of(rows, "_retail_", "!WowKitErrors") == "Linked"
            and os.path.isfile(recorder),
            "kit error recorder linked along with the addons",
        )

        again = last_json(run([link, "-Path", src, "-Root", wow, "-PassThru"]).stdout) or []
        assert_that(
            sum(1 for row in again if row.get("Status") == "AlreadyLinked") == 6
            and sum(1 for row in again if row.get("Status") == "Skipped") == 2,
            "second run leaves correct links alone",
        )

        one = last_json(run([link, "-Path", os.path.join(src, "Both"), "-Root", wow, "-Remove", "-PassThru"]).stdout) or []
        assert_that(
            len(one) == 2
            and sum(1 for row in one if row.get("Status") == "Unlinked") == 2
            and os.path.exists(os.path.join(forever_addons, "ForeverOnly"))
            and wowkit.is_link(os.path.join(forever_addons, "!WowKitErrors")),
            "-Path <one addon> touches only that addon",
        )

        removed = last_json(run([
            link, "-Path", src, "-Root", wow, "-Remove", "-NoDevAddons", "-PassThru",
        ]).stdout) or []
        assert_that(
            sum(1 for row in removed if row.get("Status") == "Unlinked") == 2
            and not os.path.exists(os.path.join(forever_addons, "ForeverOnly"))
            and not os.path.exists(os.path.join(forever_addons, "Both"))
            and os.path.isfile(os.path.join(src, "Both", "Both.toc")),
            "-Remove unlinks, sources intact",
        )
        assert_that(
            wowkit.is_link(os.path.join(forever_addons, "!WowKitErrors")),
            "-NoDevAddons leaves the error recorder alone",
        )

        gone = last_json(run([link, "-Path", src, "-Root", wow, "-Remove", "-PassThru"]).stdout) or []
        recorder_source = os.path.join(ROOT, "devaddons", "!WowKitErrors", "!WowKitErrors.toc")
        assert_that(
            sum(1 for row in gone if row.get("Status") == "Unlinked") == 2
            and not os.path.exists(os.path.join(forever_addons, "!WowKitErrors"))
            and not os.path.exists(os.path.join(retail_addons, "!WowKitErrors"))
            and os.path.isfile(recorder_source),
            "-Remove of the folder unlinks the error recorder too, its source intact",
        )
    except OSError as exc:
        if "access is denied" in str(exc).lower():
            host("  SKIP  junction creation blocked by sandbox (mklink /J denied)")
        else:
            raise
    finally:
        unlink_dir(forever_addons)
        unlink_dir(retail_addons)
        if not keep:
            shutil.rmtree(tmp, ignore_errors=True)
        else:
            host(f"  kept {tmp}")

    example = os.path.join(os.path.dirname(os.path.dirname(ROOT)), "examples", "HelloForever")
    if os.path.isdir(example):
        host("Example HelloForever:")
        code, checked = invoke_check(example, ("forever", "retail", "classic_era"))
        errors = checked["Errors"] if checked else "?"
        warns = checked["Warnings"] if checked else "?"
        assert_that(
            code == 0 and checked and checked["Errors"] == 0 and checked["Warnings"] == 0,
            f"example is clean ({errors} errors, {warns} warnings)",
        )

    host("Extended static rules, batch Find-WowApi & Prepare-WowReview:")
    tmp = os.path.join(temp_base, "wowkit-reviewtest-" + uuid.uuid4().hex[:8])
    os.makedirs(tmp)
    try:
        run([
            os.path.join(SCRIPTS, "New-WowAddon.py"),
            "-Name", "KitRules", "-OutDir", tmp,
            "-Author", "selftest", "-Icon", "INV_Misc_Gear_01", "-EditMode",
        ])
        rules_dir = os.path.join(tmp, "KitRules")
        bad_lua = os.path.join(rules_dir, "Core.lua")
        many_locals = "local " + ", ".join(f"v{i}" for i in range(176)) + " = 0"
        extra_code = "\r\n".join([
            "local function CheckSecrets(bar, cd)",
            "  local okName = UnitName('player')",
            "  if okName and not issecretvalue(okName) and okName ~= '' then end",
            "  if UnitHealth('player') < 100 then end",
            "  local hp = UnitHealth('player')",
            "  if hp < 50 then end",
            "  local safeHp = UnitHealth('player')",
            "  if safeHp ~= nil and not issecretvalue(safeHp) and safeHp < 50 then end",
            "  bar:SetTimerDuration(UnitCastingDuration('target'))",
            "  bar:SetValue(UnitHealth('player'))",
            "  CloseAllBags()",
            "  CloseAllBags() -- taint-call: ok",
            "  cd:SetCooldownFromDurationObject(d)",
            "  ContainerFrame1:UnregisterAllEvents()",
            "  local tbl = { MANA = 1, SetChecked = true }",
            "  return tbl",
            "end",
            "ToggleAllBags = function() end",
            "local function BadScopes()",
            "  " + many_locals,
            "end",
        ])
        append_ascii(bad_lua, extra_code)
        edit_lua = os.path.join(rules_dir, "EditMode.lua")
        append_ascii(edit_lua, 'local function BadEdit(frame)\r\n  local dlg = ns.EditMode.CreateDialog("D", "T")\r\n  dlg:SetPoint("CENTER")\r\n  ns.EditMode.Attach(frame, { dialog = dlg })\r\n  frame:SetScript("OnUpdate", function() end)\r\nend')

        _rc, rcheck = invoke_check(rules_dir)
        assert_that(has(rcheck, "secret-value", "warn"), "file-wide issecretvalue no longer silences unguarded secret ops")
        secret_warns = [f for f in (rcheck.get("Findings") or []) if f["Rule"] == "secret-value" and f["Severity"] == "warn"]
        assert_that(len(secret_warns) == 2, f"catches both same-line and 1-hop unguarded secrets without flagging guarded/nil checks (got {len(secret_warns)})")
        assert_that(has(rcheck, "secret-args", "warn"), "flags secret value passed to AllowedWhenUntainted :SetTimerDuration")
        taint_calls = [f for f in (rcheck.get("Findings") or []) if f["Rule"] == "taint-call" and f["Severity"] == "warn"]
        assert_that(len(taint_calls) == 2, f"flags CloseAllBags and SetCooldownFromDurationObject while respecting '-- taint-call: ok' (got {len(taint_calls)})")
        taint_hooks = [f for f in (rcheck.get("Findings") or []) if f["Rule"] == "taint-hook" and f["Severity"] == "warn"]
        assert_that(len(taint_hooks) == 1, f"flags ToggleAllBags global overwrite without flagging table keys (got {len(taint_hooks)})")
        assert_that(has(rcheck, "taint-unregister", "warn"), "flags UnregisterAllEvents on Blizzard ContainerFrame1")
        assert_that(has(rcheck, "editmode-onupdate", "warn"), "flags SetScript('OnUpdate') on EditMode.Attach frame")
        assert_that(has(rcheck, "editmode-openfor", "warn"), "flags :SetPoint on EditMode.CreateDialog")
        assert_that(has(rcheck, "local-limit", "warn"), "flags >=175 active locals approaching Lua's 200-local limit")

        no_info_proc = run([os.path.join(SCRIPTS, "Test-WowAddon.py"), "-Path", rules_dir, "-NoInfo", "-Json"])
        no_info = json.loads(no_info_proc.stdout)
        assert_that(not any(f["Severity"] == "info" for f in no_info.get("Findings") or []), "-NoInfo omits info findings")

        api_proc = run([os.path.join(SCRIPTS, "Find-WowApi.py"), "UnitHealth", ":SetTimerDuration"])
        assert_that(
            "SecretReturns" in api_proc.stdout and "AllowedWhenUntainted" in api_proc.stdout and "SimpleStatusBarAPI" in api_proc.stdout,
            "Find-WowApi batches multiple patterns and reports ScriptObject SecretArguments",
        )
        ev_proc = run([os.path.join(SCRIPTS, "Find-WowApi.py"), "UNIT_SPELLCAST_CHANNEL_STOP", "-Events"])
        assert_that("SecretWhenUnitSpellCastRestricted" in ev_proc.stdout, "Find-WowApi -Events reports SecretWhen* event payloads")
        if os.path.isfile(os.path.join(ROOT, "data", "ui-source", "forever", "INDEX.tsv")):
            ui_proc = run([os.path.join(SCRIPTS, "Find-WowApi.py"), "ContainerFrameItemButton_OnClick", "-UiSource"])
            assert_that(
                "Mainline/ContainerFrame.lua" in ui_proc.stdout and "/Vanilla/" not in ui_proc.stdout,
                "Find-WowApi -UiSource filters INDEX.tsv to Forever-loaded folders",
            )

        # Prepare-WowReview: untracked addon -> subagent-full, skips EditModeDialog.lua, extracts NOTES.md
        with open(os.path.join(rules_dir, "NOTES.md"), "w", encoding="utf-8") as nh:
            nh.write("# Notes\n## Hard Rules\n- Never reparent ChatFrame1.\n")
        pkt_proc = run([os.path.join(SCRIPTS, "Prepare-WowReview.py"), "-Path", rules_dir, "-NoLuacheck", "-Json"])
        pkt = json.loads(pkt_proc.stdout)
        assert_that(pkt["RecommendedMode"] == "subagent-full", "untracked addon defaults to subagent-full")
        assert_that(any("EditModeDialog.lua" in s for s in pkt["SkippedFiles"]), "Prepare-WowReview skips unmodified EditModeDialog.lua")
        assert_that(any("Never reparent ChatFrame1" in n for n in pkt["NotesSummary"]), "Prepare-WowReview extracts NOTES.md hard rules")
        assert_that(any("UnitHealth" in a for a in pkt["ApiAnnotations"]), "Prepare-WowReview pre-annotates secret APIs")

        # Prepare-WowReview inside a git repo: small clean diff -> inline, taint diff -> subagent-diff
        if shutil.which("git"):
            git_dir = os.path.join(tmp, "gitrepo")
            os.makedirs(git_dir)
            run([
                os.path.join(SCRIPTS, "New-WowAddon.py"),
                "-Name", "KitGit", "-OutDir", git_dir,
                "-Author", "selftest", "-Icon", "INV_Misc_Gear_01",
            ])
            g_addon = os.path.join(git_dir, "KitGit")
            subprocess.run(["git", "init"], cwd=git_dir, capture_output=True)
            subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=git_dir, capture_output=True)
            subprocess.run(["git", "config", "user.name", "test"], cwd=git_dir, capture_output=True)
            subprocess.run(["git", "add", "."], cwd=git_dir, capture_output=True)
            subprocess.run(["git", "commit", "-m", "init"], cwd=git_dir, capture_output=True)

            append_ascii(os.path.join(g_addon, "Core.lua"), "ns.STEP = 4")
            inline_pkt = json.loads(run([os.path.join(SCRIPTS, "Prepare-WowReview.py"), "-Path", g_addon, "-NoLuacheck", "-Json"]).stdout)
            assert_that(inline_pkt["RecommendedMode"] == "inline", f"small clean diff recommends inline mode (got {inline_pkt['RecommendedMode']})")

            append_ascii(os.path.join(g_addon, "Core.lua"), "hooksecurefunc('OpenAllBags', function() end)")
            diff_pkt = json.loads(run([os.path.join(SCRIPTS, "Prepare-WowReview.py"), "-Path", g_addon, "-NoLuacheck", "-Json"]).stdout)
            assert_that(diff_pkt["RecommendedMode"] == "subagent-diff", f"hook/taint diff recommends subagent-diff mode (got {diff_pkt['RecommendedMode']})")
    finally:
        if not keep:
            shutil.rmtree(tmp, ignore_errors=True)
        else:
            host(f"  kept {tmp}")

    host("")
    host(f"{PASSED} passed, {FAILED} failed")
    raise SystemExit(1 if FAILED else 0)


if __name__ == "__main__":
    main(sys.argv[1:])
