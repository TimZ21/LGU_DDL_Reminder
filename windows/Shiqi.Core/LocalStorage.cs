using System.Text.Json;
using System.Text.Json.Serialization;

namespace Shiqi.Core;

public interface ISnapshotStorage
{
    Snapshot Load();
    void Save(Snapshot snapshot);
}

public sealed class LocalStorage(string directory) : ISnapshotStorage
{
    public static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase, IgnoreReadOnlyProperties = true, WriteIndented = true,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };
    public string DirectoryPath { get; } = directory;
    public Snapshot Load()
    {
        var path = Path.Combine(DirectoryPath, "deadlines.json");
        if (!File.Exists(path)) return new();
        var data = JsonSerializer.Deserialize<Snapshot>(File.ReadAllBytes(path), JsonOptions)
            ?? throw new InvalidDataException("Saved data is empty.");
        data.Validate();
        return data;
    }
    public void Save(Snapshot snapshot)
    {
        snapshot.Validate();
        Directory.CreateDirectory(DirectoryPath);
        var path = Path.Combine(DirectoryPath, "deadlines.json");
        var temporary = Path.Combine(DirectoryPath, ".deadlines-" + Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            var bytes = JsonSerializer.SerializeToUtf8Bytes(snapshot, JsonOptions);
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            {
                file.Write(bytes); file.Flush(true);
            }
            if (File.Exists(path))
            {
                // Do not replace a corrupted file or its backup, even after a successful first load.
                _ = Load();
                File.Replace(temporary, path, Path.Combine(DirectoryPath, "deadlines.backup.json"));
            }
            else File.Move(temporary, path);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}

public interface IFeedCredential
{
    string? Read();
    void Write(string value);
    void Delete();
}

// Used only by the isolated demo/preview and tests. Real Windows connections use Credential Manager.
public sealed class MemoryCredential : IFeedCredential
{
    private string? value;
    public string? Read() => value;
    public void Write(string next) => value = next;
    public void Delete() => value = null;
}
