from dataclasses import dataclass
import numpy as np

def rgb_csv(color: str):
    color = color.lstrip("#")
    return np.array(tuple(int(color[i:i+2], 16)/255 for i in (0, 2, 4)))



@dataclass
class Colors():
    darkest: np.ndarray
    dark: np.ndarray
    light: np.ndarray
    lightest: np.ndarray

    shadow: np.ndarray

    primary: np.ndarray
    secondary: np.ndarray
    tertiary: np.ndarray
    error: np.ndarray

    white: np.ndarray
    gray: np.ndarray
    black: np.ndarray

    red: np.ndarray
    yellow: np.ndarray
    green: np.ndarray
    blue: np.ndarray
    purple: np.ndarray

    @property
    def brown(self):
        return (self.red * 0.5 + self.yellow * 0.5) * .7 + self.black * 0.3

    @property
    def darkbrown(self):
        return (self.red * 0.5 + self.yellow * 0.5) * .4 + self.black * 0.6


light = Colors(
    darkest=np.array(({{ colors.surface_container_lowest.light.rgb_csv }}))/255,
    dark=np.array(({{ colors.surface_container_low.light.rgb_csv }}))/255,
    light=np.array(({{ colors.surface_container_high.light.rgb_csv }}))/255,
    lightest=np.array(({{ colors.surface_container_highest.light.rgb_csv }}))/255,

    shadow=np.array(({{ colors.surface_container_low.dark.rgb_csv | set_saturation 100 }}))/255,

    primary=np.array(({{ colors.primary.dark.rgb_csv }}))/255,
    secondary=np.array(({{ colors.secondary.dark.rgb_csv }}))/255,
    tertiary=np.array(({{ colors.tertiary.dark.rgb_csv }}))/255,
    error=np.array(({{ colors.error.dark.rgb_csv }}))/255,

    white=np.array(({{ colors.terminal_bright_white.dark.rgb_csv }}))/255,
    gray=np.array(({{ colors.terminal_bright_black.dark.rgb_csv }}))/255,
    black=np.array(({{ colors.terminal_normal_black.dark.rgb_csv }}))/255,

    red=np.array(({{ colors.terminal_normal_red.dark.rgb_csv }}))/255,
    yellow=np.array(({{ colors.terminal_normal_yellow.dark.rgb_csv }}))/255,
    green=np.array(({{ colors.terminal_normal_green.dark.rgb_csv }}))/255,
    blue=np.array(({{ colors.terminal_normal_blue.dark.rgb_csv }}))/255,
    purple=np.array(({{ colors.terminal_normal_magenta.dark.rgb_csv }}))/255,
)


dark = Colors(
    darkest=np.array(({{ colors.surface_container_lowest.dark.rgb_csv }}))/255,
    dark=np.array(({{ colors.surface_container_low.dark.rgb_csv }}))/255,
    light=np.array(({{ colors.surface_container_high.dark.rgb_csv }}))/255,
    lightest=np.array(({{ colors.surface_container_highest.dark.rgb_csv }}))/255,

    shadow=np.array(({{ colors.surface_container_low.dark.rgb_csv | set_saturation 100 }}))/255,

    primary=np.array(({{ colors.primary.dark.rgb_csv }}))/255,
    secondary=np.array(({{ colors.secondary.dark.rgb_csv }}))/255,
    tertiary=np.array(({{ colors.tertiary.dark.rgb_csv }}))/255,
    error=np.array(({{ colors.error.dark.rgb_csv }}))/255,

    white=np.array(({{ colors.terminal_bright_white.dark.rgb_csv }}))/255,
    gray=np.array(({{ colors.terminal_bright_black.dark.rgb_csv }}))/255,
    black=np.array(({{ colors.terminal_normal_black.dark.rgb_csv }}))/255,

    red=np.array(({{ colors.terminal_normal_red.dark.rgb_csv }}))/255,
    yellow=np.array(({{ colors.terminal_normal_yellow.dark.rgb_csv }}))/255,
    green=np.array(({{ colors.terminal_normal_green.dark.rgb_csv }}))/255,
    blue=np.array(({{ colors.terminal_normal_blue.dark.rgb_csv }}))/255,
    purple=np.array(({{ colors.terminal_normal_magenta.dark.rgb_csv }}))/255,
)

colors = {
    "light": light,
    "dark": dark,
}

# mode = "{{ mode }}"
# if mode == "light":
#     c = light
# elif mode == "dark":
#     c = dark


