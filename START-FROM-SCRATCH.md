# Start from scratch

This guide assumes nothing: not that you've coded, used a terminal, or own a particular computer. Follow it top to
bottom. Every command is shown exactly. If a step fails, the **If it goes wrong** box under it says what to do.

You will end with: Claude Code installed, this kit's safety guards on, a first project on GitHub, and the habit of
working in small, tested steps.

---

## 0. What you need, honestly

| You need | Why | Cost |
|---|---|---|
| A computer you can install software on: a Mac (macOS 13 or newer), Windows 10 or 11, or Linux (Ubuntu 22.04 or newer), with 4 GB of RAM | Claude Code runs on it | what you have |
| An internet connection | Claude runs in the cloud | — |
| A Claude plan that includes Claude Code: **Pro** or higher | The free plan doesn't include Claude Code | Pro is $20/month (less if paid yearly). See [claude.com/pricing](https://claude.com/pricing) for current prices |
| A GitHub account | Where your code lives, and how sessions share work | free |

**No computer of your own?** Claude Code also runs in a web browser at [claude.ai/code](https://claude.ai/code), from
any device including a phone, as long as you have a paid plan and a GitHub account. The guards in this kit install
on a computer, so the browser route is for getting started; come back to this guide when you have a machine.

> Prices and requirements were read from the official pages on 2026-10-09. Check the links above; they change.

---

## 1. Open a terminal (2 minutes)

A terminal is a window where you type commands. Each command is one line; press **Enter** to run it.

- **Mac:** press `Cmd + Space`, type `Terminal`, press Enter.
- **Windows:** press the Windows key, type `PowerShell`, press Enter.
- **Linux:** press `Ctrl + Alt + T`.

Try it: type `echo hello` and press Enter. It prints `hello`. That's all a terminal is.

---

## 2. Install the tools (15 minutes)

### Mac
1. Install Homebrew (a tool installer): copy the one line from [brew.sh](https://brew.sh), paste it into Terminal,
   press Enter, and follow what it prints. At the end it shows two more lines to run; run them.
2. Install git, the GitHub tool, jq, and a terminal that splits into panes:
   ```
   brew install git gh jq
   brew install --cask ghostty
   ```
3. Install Claude Code:
   ```
   curl -fsSL https://claude.ai/install.sh | bash
   ```

### Windows
Use WSL (a Linux environment inside Windows); the kit's guards are shell scripts.
1. In PowerShell: `wsl --install`, then restart when asked. Open **Ubuntu** from the Start menu and create a user.
2. Inside Ubuntu, follow the **Linux** steps below.

### Linux (and Windows inside WSL)
Ubuntu 22.04 or newer:
```
sudo apt update && sudo apt install -y git jq zsh make python3
sudo apt install -y gh || echo "gh not in your apt: install it from https://cli.github.com (Linux, apt)"
chsh -s "$(which zsh)"     # make zsh your shell (the session commands are zsh); then log out and back in
curl -fsSL https://claude.ai/install.sh | bash
```

### Then, everyone
```
claude --version      # prints a version number such as 2.1.295 (Claude Code)
git config --global user.name "Your Name"
git config --global user.email "you@example.com"   # use the email on your GitHub account
gh auth login         # choose GitHub.com, HTTPS, and log in with a browser
claude                # log in to your Claude account when asked, then type /exit
```

> **If it goes wrong:** `command not found: claude` means a new terminal is needed: close the window and open a
> new one. Still failing? Run `claude doctor`; it says what's wrong and how to fix it.

---

## 3. Install this kit (10 minutes)

1. Put the kit in your home folder:
   ```
   cd ~ && git clone https://github.com/RahulModugula/agentic-starter-kit.git
   ```
   (Or unzip `agentic-starter-kit.zip` into your home folder, so you have `~/agentic-starter-kit`.)
2. **Preview first. This changes nothing:**
   ```
   cd ~/agentic-starter-kit && ./install.sh
   ```
   It lists every file it would add or change, with the differences.
3. Install:
   ```
   ./install.sh --apply
   ```
   It **backs up** your existing Claude settings first, then installs the guards, roles, settings and commands.
   Undo it any time with `./install.sh --rollback`.
4. Add the session commands to your shell, then open a new terminal window:
   ```
   echo 'source ~/.claude/lanes.zsh' >> ~/.zshrc
   ```
5. Check everything works: `make check`. It runs every test in the kit (about a minute) and prints
   `ALL TESTS PASSED`, then a safety scan that prints `SCAN CLEAN`.

> **If it goes wrong:** `./install.sh --apply` refuses on an old Claude Code. Run `claude update`, then retry.

---

## 4. Your first project (10 minutes)

```
mkdir -p ~/work/my-app && cd ~/work/my-app
git init && git commit --allow-empty -m "start"
gh repo create my-app --private --source . --push
```
Open `~/.claude/lanes.zsh` in any text editor and set the two lines near the top:
```
REPOS=(my-app)
MAIN_REPO=my-app
```
(That file is linked to `~/agentic-starter-kit/claude/lanes.zsh`, so you're editing the kit's copy. That's
expected; `git status` in the kit will show it as changed.)

Let the kit run your project's checks before a session says "done" (only for projects you trust):
```
~/agentic-starter-kit/bin/trust-repo.sh ~/work/my-app
```

---

## 5. Check the safety guard works (5 minutes)

1. In your terminal, run `coord`. A Claude session opens in `~/work/my-app`. This is the **coordinator**.
2. Split the window (Ghostty on a Mac: `Cmd + D`; anywhere else, just open a second terminal window) and run
   `lane 1`. A second session opens in its own copy of the project.
   This is a **lane**.
3. In lane 1, type: `Try to push to main.` The guard **blocks** it. That's the kit doing its job: changes go
   through a branch and a review, never straight to main.

---

## 6. Build something, safely

Tell the coordinator what you want, in plain words: *"A web page that shows today's weather for my city."* It
replies with a short plan and a `lane <name>` command for each piece of work. Run each in a new split.

The lane will:
1. **write tests first**, the checks that prove the feature works, and watch them fail;
2. write the code until the tests pass;
3. run all the checks: the kit won't let a session say "done" while your project's checks fail;
4. open a pull request (a proposed change) and report "ready".

Then run `lane verifier` once. It reviews each pull request with fresh eyes and posts `VERIFIED` or a list of
problems. The coordinator merges only verified work.

**You approve anything risky** (spending money, deleting things, deploying) in the pane that asks. Nobody else can
approve for you; that's deliberate.

---

## 7. When something goes wrong

| Situation | Do this |
|---|---|
| Claude is going the wrong way | Press `Esc` to stop it. Say what you want instead. |
| You want to undo Claude's last edits | Press `Esc` twice and choose a point to rewind to (`/rewind`). |
| Rewind didn't undo it (shell commands aren't tracked) | `git status` shows what changed; `git restore <file>` undoes a file. |
| The session is confused after a long chat | `/clear` starts fresh. Put anything it must remember in the project's `CLAUDE.md`. |
| You're worried about cost | `/usage` shows how much of your plan you've used; the status line shows it all the time. |
| You want to undo the kit itself | `cd ~/agentic-starter-kit && ./install.sh --rollback` |

---

## 8. Five rules that keep you safe

1. **Never paste passwords, keys or tokens into the chat.** Conversations are saved on your computer.
2. **Commit before big changes** (`git commit`), so there's always a point to go back to.
3. **Read what you approve.** If a prompt asks to delete, deploy or spend, and you didn't expect it, say no.
4. **Web pages and files can contain instructions aimed at the AI.** The kit tells Claude to treat them as data;
   you should too.
5. **Core code gets a human look.** If the kit flags a change as `human` review, read the files it lists before
   approving. See `docs/REVIEW-TIERS.md`.

---

## 9. What to learn next

- **First week:** run `/init` in your project to draft its `CLAUDE.md`, then cut it to the few lines that matter.
  Use `/clear` between unrelated tasks. Run `make check` in the kit after any change you make to it.
- **When you're comfortable:** read `docs/ARCHITECTURE.md` (how every guard works and why), `docs/TESTING.md` (how the
  agents' code gets tested), and `docs/REVIEW-TIERS.md` (what needs a human).

## Words you'll see

- **Repository (repo):** a project folder tracked by git.
- **Branch:** a separate line of work, so changes don't touch the main version until reviewed.
- **Pull request (PR):** a proposed change, waiting for review.
- **Worktree:** a second copy of a repo on disk, so two sessions don't trip over each other.
- **Hook:** a small script Claude Code runs automatically at set moments, for example before running a command.
  The kit's guards are hooks.
- **Merge:** accepting a pull request into the main version.
