# Third-Party Asset Attribution

## Gothic window

"Gothic window" by Paulina (@Byakko) is licensed under Creative Commons
Attribution 4.0 International (CC BY 4.0).

- Model: https://sketchfab.com/3d-models/gothic-window-b08907202ad54cc982cbc111da27f37c
- Creator: https://sketchfab.com/Byakko
- License: https://creativecommons.org/licenses/by/4.0/

The asset is duplicated as the three front ornamental window modules. Its original
carved-stone PBR material is preserved and it is combined with original facade,
reveal, sill, and depth geometry.

## Medieval Blocks 03

"Medieval Blocks 03" by Rob Tuytel is provided by Poly Haven under CC0.

- Asset: https://polyhaven.com/a/medieval_blocks_03
- Creator: https://polyhaven.com/humans
- License: https://polyhaven.com/license

The 2K diffuse, OpenGL normal, and roughness maps remain as a subtle mineral
variation source for the procedural rough-stone sill.

## Rock 01

"Rock 01" by Rob Tuytel is provided by Poly Haven under CC0.

- Asset: https://polyhaven.com/a/rock_01
- Creator: https://polyhaven.com/humans
- License: https://polyhaven.com/license

The 2K diffuse, OpenGL normal, and roughness maps provide restrained fine-grain
stone detail on the carved columns. The material deliberately uses a weak
normal response and no displacement so the columns remain smooth silhouettes.

## Rabdentse Ruins Wall

"Rabdentse Ruins Wall" by Amal Kumar is provided by Poly Haven under CC0.

- Asset: https://polyhaven.com/a/rabdentse_ruins_wall
- Creator: https://polyhaven.com/humans
- License: https://polyhaven.com/license

The 2K diffuse, OpenGL normal, roughness, and ambient-occlusion maps are used on
the deep side reveals. Their scale and saturation are reduced in the Godot
material so they read as broad, dark, timeworn fortress masonry.

## Cochem Imperial Castle, Germany

"Cochem Imperial Castle, Germany" by Dok11 is licensed under Creative Commons
Attribution 4.0 International (CC BY 4.0). Source video attribution is retained
from the SuperSplat listing.

- Scene: https://superspl.at/scene/9b18007e
- Creator: https://superspl.at/user?id=dok11
- Source footage: https://www.pexels.com/@marros/gallery/?filter=videos
- License: https://creativecommons.org/licenses/by/4.0/

## Sumela Monastery Cliffside

"Sumela Monastery Cliffside" by Dok11 is licensed under Creative Commons
Attribution 4.0 International (CC BY 4.0). The reconstruction uses source video
by Kenan Turguc on Pexels.

- Scene: https://superspl.at/scene/5f03cdcb
- Creator: https://superspl.at/user?id=dok11
- Source footage: https://www.pexels.com/video/33550575/
- License: https://creativecommons.org/licenses/by/4.0/

## Sovinec Castle

"Sovinec castle" by Pavel Matousek is licensed under Creative Commons
Attribution 4.0 International (CC BY 4.0).

- Scene: https://superspl.at/scene/0f5e0540
- Creator: https://superspl.at/user?id=matousekfoto2
- License: https://creativecommons.org/licenses/by/4.0/

## Godot Gaussian Splatting

The desktop Gaussian renderer is Godot Gaussian Splatting (GDGS) by mianzhi,
used under the MIT License. Its license is vendored at `addons/gdgs/LICENSE`.

- Project: https://github.com/ReconWorldLab/godot-gaussian-splatting
- Version: 2.2.0
- License: https://github.com/ReconWorldLab/godot-gaussian-splatting/blob/gdgs_2.2.0/LICENSE

## Procedural Gaussian weather references

The outdoor falling-weather implementation is an original Godot/GDGS port of
the procedural Gaussian-weather architecture published in the MIT-licensed
PlayCanvas Engine. It uses the same high-level idea of deterministic looping
weather Gaussians inside a bounded volume; it does not vendor PlayCanvas code.

- Source reference: https://github.com/playcanvas/engine/blob/main/scripts/esm/gsplat/gsplat-weather.mjs
- Procedural splat documentation: https://developer.playcanvas.com/user-manual/gaussian-splatting/building/procedural-splats/
- License: https://github.com/playcanvas/engine/blob/main/LICENSE

Snow accumulation is independently implemented from the algorithm described by
Weather-Magician: Gaussian-normal initialization, local-plane filtering, and
random tangent-plane densification. No Weather-Magician source code is included.

- Project: https://weathermagician.github.io/
- Paper: https://arxiv.org/abs/2505.19919
