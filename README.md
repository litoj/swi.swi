# `swi.swi`

What's up with the name? You tell me:

- shorter and easier to type when accessing the api
- simple way to say a lua package is made for swayimg - like `.nvim` for neovim
- _Swayimg neoWim-like Interface_
  - allows vim-style mappings like `<C-S-Del>`, `<C-.>`…
  - eventloop system based on neovim lua autocommands - almost everything is listenable
  - variables are now all 2-way accessible variables, not just setter methods
- _Superb Wayland Imager_
  - because swayimg is already _the_ waylang imager and this only makes it better
  - because the api is simpler and efficient, yet offers more features and practicality than the
    original

## ✨ Features

### Api accessibility

The whole api can now be set through variables wherever it makes sense.

Common actions like switching images and moving around the image have been made into standalone
functions to make it simpler for mapping:

```lua
v.map('Right', v.go.next)
v.step.default_size = 100 -- px
v.map('k', v.step.up)
v.map('Alt+k', function() v.step.by(70,70) end)
```

### ⚡️ Eventloop

Lets you listen to almost anything and trigger your own events to allow adding extra features that
need simple ways of communication.

Example: displaying the current number of marked images

```lua
g.text.topright = { 'Image: {list.index}/{list.total}', 'Marked: 0' }
e.subscribe {
	event = 'OptionSet',
	pattern = 'swi.imagelist.marked.size',
	callback = function(event) g.text.topright = { g.text.topright[1], 'Marked: ' .. event.data } end,
}
```

### Style-agnostic keybinds

Map as many keys or mouse actions in gui- or vim-style or anything in between

```lua
--        gui,      vim,    imv-gui,  chaos (please don't!)
g.map({ 'Shift+m', '<S- >', 'Alt-h',   'C-S+Alt-_' }, function()
	l.marked.set_current 'toggle'
	g.go.left()
end)
```

Map a shell command more easily than ever, even marked batches:

- `%f`: `'`-quoted current file: `v.map('Ctrl-e', 'xdg-open %f')`
- `%s`/`%m`: `'`-quoted marked/selected files: `v.map('A-s', 'dragon-drop -x -A %s')`
  - until we get an alternative dnd mapping for dragging the whole selection
- `%`: unquoted current (like in 4.x): `v.map('', [[bash -c '$(which trash || echo rm) "%"']])`

### Better exif display in text layer

By default swayimg spits out whatever value exiv2 sees in the exif data, but the format often
differs between devices and rational number get stored in unconventional formats like `700/10000`.
They also use long tag names and you have to know in which category to look for them.

No more. Now you can either use `swi.text.format_exif` yourself, or even better - just put the
desired exif tag in the same template format as the other image values - only requirement is to keep
the casing.

Example:

```lua
v.text.topleft = {
  'File: {name}', 'Size: {sizehr}', 'Res: {frame.width}x{frame.height}',

  'Exposure: {ExposureTime} s',
  'ISO: {ISOSpeedRatings}',
  'DR: {Exif.Fujifilm.DynamicRange}', -- full path
  'FNumber: {FNumber}',
  'FL: {FocalLength} mm', -- auto-translates to Exif.Photo.FocalLength
  'Rating: {Rating}' -- auto-translates to Exif.Image.Rating
}
```

### New scaling modes

- `keep_by_xxx`:
  - useful for comparing identical images of different sizes
  - you will stay zoomed into the same spot of the image even if the other image is half the
    resolution
  - available metrics: …`width`/`height`/`size` - like `width`/`height`/`optimal` scaling

### ⚠️ Limitations

True eventloop used by swayimg internally is still inaccessible, so we cannot listen for image
updates and save image state (like scale, position, etc.) before the image gets changed.

## 🚀 Geting started

Clone the repo into your swayimg config to `swi` _(not `swi.swi`!)_.

```sh
git clone https://github.com/litoj/swi ~/.config/swayimg/swi
```

_Don't forget to add it to `.gitignore`, if you version your dotfiles_

### Keep and convert your 4.x INI config

```sh
luajit ~/.config/swayimg/swi/convert.lua > ~/.config/swayimg/init.lua
```

Now you can open them side by side to see how the structure has changed.

If you want to keep using your old config, you can also load it on startup dynamically:

```lua
-- ~/.config/swayimg/init.lua
require('swi.convert').load()

-- full api now also available
```

### Use the API

To start using the api you only need to load the main module. However, if you also want to use all
the main APIs as globals, you can also load `swi.globals` to have easier access to them

```lua
-- ~/.config/swayimg/init.lua
-- makes the api accessible through the `swi` global variable
-- you can also just save it to whatever you want
require 'swi.api'
-- or through first-letter globals (except: swi.imagelist -> `l` - not `i`)
require 'swi.globals'

-- now you can use all options as variables and make intricate behaviour using eventloop hooks
```

### Better dev experience in NeoVim

If you already use _lua_ls_ you only need to load include the original swayimg api definitions from
which _swi_ reuses the type definitions:

```lua
settings.Lua.workspace.library = {'/usr/share/swayimg/swayimg.lua'}
```

# License

Do whatever you please.
