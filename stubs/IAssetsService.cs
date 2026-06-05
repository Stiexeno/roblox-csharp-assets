using System.Collections.Generic;

namespace Assets
{
    // Tag-based asset registry. Assets are addressed by string keys
    // (unique, one-to-one) and labels (shared, one-to-many). The
    // service queries CollectionService at lookup time — no setup
    // required beyond tagging the Instance in Studio with the
    // appropriate "AssetKey:<name>" / "AssetLabel:<name>" tag.
    //
    // Renaming or moving an Instance doesn't break the lookup: tags
    // are decoupled from the Instance's name and path.
    public interface IAssetsService
    {
        // ModuleScript whose require() result is the asset table.
        // Throws when zero or multiple Instances share the key, or
        // when the matched Instance isn't a ModuleScript.
        T Load<T>(string key);

        // Every ModuleScript carrying the label, require()'d. Empty
        // collection when nothing's tagged. Non-ModuleScript Instances
        // sharing the label are silently skipped — use LoadAllPrefabs
        // for those.
        IEnumerable<T> LoadAll<T>(string label);

        // Returns a fresh clone of the (non-ModuleScript) Instance
        // tagged with the key. Throws on miss, duplicate, or
        // ModuleScript-typed match.
        Instance LoadPrefab(string key);

        // Clones every non-ModuleScript Instance sharing the label.
        IEnumerable<Instance> LoadAllPrefabs(string label);
    }
}
