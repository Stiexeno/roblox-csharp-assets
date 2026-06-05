using System.Collections.Generic;

namespace Assets
{
    // Concrete impl is hand-written Lua under runtime/AssetsService.luau.
    // This C# stub exists so user code typechecks; the bodies never run.
    public class AssetsService : IAssetsService
    {
        public T Load<T>(string key) => default;
        public IEnumerable<T> LoadAll<T>(string label) => default;
        public Instance LoadPrefab(string key) => default;
        public IEnumerable<Instance> LoadAllPrefabs(string label) => default;
    }
}
