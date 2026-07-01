#pragma warning disable CS0626 // Methods are implemented in runtime/AssetsService.luau, not in this assembly.

using System.Collections.Generic;

namespace Assets
{
    // Concrete impl is hand-written Lua under runtime/AssetsService.luau.
    // This C# stub exists so user code typechecks; every member is `extern`
    // to make the "implemented elsewhere" intent explicit — nothing here runs.
    public class AssetsService : IAssetsService
    {
        public extern T Load<T>(string key);
        public extern IEnumerable<T> LoadAll<T>(string label);
        public extern Instance LoadPrefab(string key);
        public extern IEnumerable<Instance> LoadAllPrefabs(string label);
    }
}
