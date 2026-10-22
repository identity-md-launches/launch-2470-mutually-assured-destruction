# Vendored dependencies

- `OpenZeppelin/openzeppelin-contracts` `v5.1.0`: https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.1.0
  Archive SHA-256: `8a3b08cfc756437ba3343901565b18182adb42ec1e621960240a19da5d738686`.
  Vendored 6 files under `lib/openzeppelin-contracts`.

- `foundry-rs/forge-std` `v1.9.7`: https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7
  Archive SHA-256: `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`.
  Vendored 30 files under `lib/forge-std`.

OpenZeppelin contains only ERC20 and its transitive Solidity imports, plus its MIT license.
Forge Standard Library contains its `src/` tree and both upstream licenses, for tests only.
Files are unmodified upstream sources. These are ordinary files, not submodules;
no download or package installation is needed to build or test.
