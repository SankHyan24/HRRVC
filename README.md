# Hierarchical Russian Roulette for Vertex Connections - Paper Reproduction

![Dining Room](./screenshots/diningroom_hrrvc_100.png)

[![CMake](https://github.com/SankHyan24/HRRVC/actions/workflows/cmake.yml/badge.svg)](https://github.com/SankHyan24/HRRVC/actions/workflows/cmake.yml)

We reproduct the main algorithm of the paper "Hierarchical Russian Roulette for Vertex Connections" by Yusuke Tokuyoshi et al. (2019). The renderer code framework is from [glsl-pathtracer](https://github.com/knightcrawler25/GLSL-PathTracer).

Paper at https://yusuketokuyoshi.com/papers/2019/Hierarchical_Russian_Roulette_for_Vertex_Connections.pdf .

We add a naive bidirectional path tracer, and implement the HRRVC algorithm in the bidirectional path tracer. We also add a path tracer for comparison. The enviroment map and volume rendering are not implemented.
