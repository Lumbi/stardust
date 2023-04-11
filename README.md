# stardust

An N-body simulation using Metal.

It simulates gravity-like forces between 10,000 particles on the GPU using a compute kernel (that's 100,0000,000 computations per frame!).

<img src="https://user-images.githubusercontent.com/1648852/231038696-cbc4a820-d9d8-4df4-9d6c-bd79ec3c0fc6.png">

Each particle is rendered as a textured mesh using instance drawing.
It runs at about ~30 FPS on my old MacBook Pro (2018).
Mouse and WASD to move the camera around.

This exercise helped me understand better how Apple's Metal API is structured and how it differs from OpenGL.

Texture by: Joshua "JDSherbert" Herbert.
https://jdsherbert.itch.io/pbr-materials-pack-free