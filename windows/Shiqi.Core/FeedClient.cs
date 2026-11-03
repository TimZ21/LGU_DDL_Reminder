using System.Net;
using System.Text;

namespace Shiqi.Core;

public static class FeedAddress
{
    public static Uri Validate(string text)
    {
        text = text.Trim();
        if (text.StartsWith("webcal://", StringComparison.OrdinalIgnoreCase)) text = "https://" + text[9..];
        if (!Uri.TryCreate(text, UriKind.Absolute, out var uri) || uri.Scheme != "https"
            || uri.UserInfo.Length != 0 || uri.Fragment.Length != 0 || string.IsNullOrEmpty(uri.Host)
            || uri.AbsolutePath is "" or "/")
            throw new FormatException("Enter the complete HTTPS calendar sharing link / 请输入完整 HTTPS 日历共享链接");
        return uri;
    }
}

public sealed class FeedClient : IDisposable
{
    public const int MaximumBytes = 5 * 1024 * 1024;
    private readonly HttpClient client;
    private readonly TimeSpan timeout;
    public FeedClient(HttpMessageHandler? handler = null, TimeSpan? timeout = null)
    {
        this.timeout = timeout ?? TimeSpan.FromSeconds(45);
        client = new HttpClient(handler ?? new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false,
            AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate }) { Timeout = this.timeout };
    }
    public async Task<string> FetchAsync(Uri address, Settings settings, CancellationToken cancellation = default)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        deadline.CancelAfter(timeout);
        var requestCancellation = deadline.Token;
        try
        {
            var current = FeedAddress.Validate(address.AbsoluteUri);
            for (var redirects = 0; redirects <= 5; redirects++)
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, current);
                request.Headers.Accept.ParseAdd("text/calendar, text/plain;q=0.8");
                using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, requestCancellation);
                if ((int)response.StatusCode is 301 or 302 or 303 or 307 or 308)
                {
                    if (response.Headers.Location is not { } location) break;
                    var next = new Uri(current, location);
                    // A feed URL is a credential. Do not follow it to another origin, HTTP, or a URL with userinfo.
                    if (next.Scheme != "https" || next.IdnHost != address.IdnHost || next.Port != address.Port || next.UserInfo.Length != 0)
                        throw new IOException(settings.Text("已阻止跨站或不安全的日历重定向。", "Blocked an unsafe or cross-site calendar redirect."));
                    current = next; continue;
                }
                if (!response.IsSuccessStatusCode)
                    throw new IOException(settings.Text($"日历访问失败（HTTP {(int)response.StatusCode}）。请检查共享链接及校园网/VPN。", $"Calendar access failed (HTTP {(int)response.StatusCode}). Check the sharing link and campus network/VPN."));
                if (response.Content.Headers.ContentLength > MaximumBytes) throw new IOException(settings.Text("日历超过 5 MB。", "The calendar exceeds 5 MB."));
                await using var stream = await response.Content.ReadAsStreamAsync(requestCancellation);
                using var output = new MemoryStream();
                var buffer = new byte[16384];
                int count;
                while ((count = await stream.ReadAsync(buffer, requestCancellation)) > 0)
                {
                    if (output.Length + count > MaximumBytes) throw new IOException(settings.Text("日历超过 5 MB。", "The calendar exceeds 5 MB."));
                    output.Write(buffer, 0, count);
                }
                try { return new UTF8Encoding(false, true).GetString(output.ToArray()); }
                catch (DecoderFallbackException) { throw new IOException(settings.Text("日历不是有效的 UTF-8 文件。", "The calendar is not valid UTF-8.")); }
            }
            throw new IOException(settings.Text("日历重定向次数过多。", "Too many calendar redirects."));
        }
        catch (Exception e) when (e is HttpRequestException or OperationCanceledException)
        {
            if (cancellation.IsCancellationRequested) throw new OperationCanceledException(cancellation);
            // Never surface exceptions that might contain the private subscription URL.
            throw new IOException(settings.Text("无法连接日历。请检查网络、校园 VPN 和共享链接；原有数据已保留。", "Could not connect. Check your network, campus VPN and sharing link. Existing data is kept."));
        }
    }
    public void Dispose() => client.Dispose();
}
