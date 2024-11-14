# cursorcolumn
![License](https://img.shields.io/github/license/jamescherti/cursorcolumn.el)

The `cursorcolumn.el` Emacs package visually highlights the current column where the cursor is positioned by drawing a vertical line.

This package is a fork of vline.el and offers improvements in performance and bug fixes, making use of more modern Emacs functions and effectively superseding the vline.el package.

## Features

- **Performance Optimizations**: Improved performance over the original vline.el, ensuring smoother interactions, especially in large buffers.
- **Bug fixes**: Addressed issues in vline.el (such as [#1](https://github.com/buzztaiki/vline/pull/1), which the vline author hasn't merged since Feb. 12, 2024), ensuring smoother interactions, especially in large buffers.

## Installation

### Install with straight

To install `cursorcolumn` with `straight.el`:

1. If you haven't already done so, [add the straight.el bootstrap code](https://github.com/radian-software/straight.el?tab=readme-ov-file#getting-started) to your init file.

2. Add the following code to your Emacs init file:
```
(use-package cursorcolumn
  :ensure t
  :straight (cursorcolumn
             :type git
             :host github
             :repo "jamescherti/cursorcolumn.el"))
```

## License

 Copyright (C) 2024 by James Cherti | https://www.jamescherti.com/
 Copyright (C) 2002, 2008-2021 by Taiki SUGAWARA <buzz.taiki@gmail.com>

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.

## Links

- [cursorcolumn.el @GitHub](https://github.com/jamescherti/cursorcolumn.el)
