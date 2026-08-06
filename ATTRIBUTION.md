# Attribution

The MIT licence in `LICENSE` covers my own work in this repository. The files
below are third-party and carry their own terms.

Verified by reading each file's header on 2026-08-06 — the "Header?" column is
there because two of them do **not** carry one, and a licence file that implies
otherwise is worse than none.

| File | Upstream | Author | Licence | Header? |
|---|---|---|---|---|
| `kitty/catppuccin-frappe.conf` | [catppuccin/kitty](https://github.com/catppuccin/kitty/blob/main/frappe.conf) | Pocco81 | MIT | yes |
| `kitty/catppuccin-latte.conf` | [catppuccin/kitty](https://github.com/catppuccin/kitty/blob/main/latte.conf) | Pocco81 | MIT | yes |
| `kitty/diff.conf` | [catppuccin/kitty](https://github.com/catppuccin/kitty/blob/main/themes/diff-frappe.conf) | Catppuccin Org | MIT | yes |
| `kitty/dark-theme.auto.conf` | [gruvbox-material-kitty](https://github.com/rsaihe/gruvbox-material-kitty) | Sainnhe Park | MIT | yes |
| `kitty/tokyonight_storm.conf` | [folke/tokyonight.nvim](https://github.com/folke/tokyonight.nvim) | Folke Lemaitre | MIT | yes |
| `kitty/nord.conf` | [nordtheme.com](https://www.nordtheme.com/) | Eric N. Vander Weele | **not stated** | partial — author + upstream, **no licence line** |
| `blink/tokyonight-storm.js` | Tokyo Night Storm palette, for the Blink iOS terminal | — | **not stated** | **none** — the file opens with a bare `t.prefs_.set(...)` |
| `oh-my-zsh/catppuccin.zsh-theme` | [ohmyzsh/ohmyzsh](https://github.com/ohmyzsh/ohmyzsh) `robbyrussell` | Robby Russell + contributors | MIT | derivative — lines 1-7 are `robbyrussell` commented out |
| `oh-my-zsh/cyberpunk.zsh-theme` | as above | as above | MIT | as above |

## Notes

- **`kitty/nord.conf`** names an author and an upstream but states no licence.
  Nord itself is MIT, but this file does not say so, so it is recorded as
  *not stated* rather than assumed.
- **`blink/tokyonight-storm.js`** carries no header of any kind. It is a palette
  transcription for the Blink terminal; the colour values are Tokyo Night's
  (Folke Lemaitre, MIT). Recorded here because the file itself says nothing.
- The two `oh-my-zsh/*.zsh-theme` files are **derivative**, not original: the
  first seven lines of each are oh-my-zsh's `robbyrussell` theme commented out,
  and the live `PROMPT` / `ZSH_THEME_GIT_PROMPT_*` shape follows it. The palette
  selection and the light/dark logic are mine.
- Everything under `nvim/`, `zsh/`, `colorls/`, `ipython/`, `silicon/` and
  `.ripgreprc` is my own work, as is `install.sh` and `rescue.sh`.

To re-check completeness against the tree:

```sh
comm -23 <(git ls-files | sort) <(grep -oE '`[^`]+`' ATTRIBUTION.md | tr -d '`' | sort)
```

Read the output once. Every path it prints must be work you are content to
licence MIT under your own name.
