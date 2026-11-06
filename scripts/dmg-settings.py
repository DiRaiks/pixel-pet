# dmgbuild settings for the release DMG, used by scripts/release.sh. Paths come in with -D app=…,
# -D background=… and -D icon=…. The icon spots match the arrow in Resources/DMG/background.png
# (drawn by `PixelPet --export-dmg-background`, see Sources/PixelPet/DMGBackground.swift).
import os.path

app = defines["app"]  # noqa: F821 (dmgbuild provides `defines`)
app_name = os.path.basename(app)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]  # noqa: F821

background = defines["background"]  # noqa: F821
# The height includes the 32-point title bar, so the whole 640×400 picture shows.
window_rect = ((200, 400), (640, 432))
default_view = "icon-view"
show_toolbar = False
show_sidebar = False
show_status_bar = False
show_tab_view = False
show_pathbar = False
show_icon_preview = False

icon_size = 128
text_size = 13
icon_locations = {app_name: (176, 200), "Applications": (464, 200)}
