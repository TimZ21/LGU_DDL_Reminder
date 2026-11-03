using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Layout;
using Avalonia.Media;

namespace Shiqi.Desktop;

internal static class Ui
{
    public static readonly IBrush Purple = Brush.Parse("#750F6D"), Gold = Brush.Parse("#DDA300"), Ink = Brush.Parse("#27212C"), Muted = Brush.Parse("#716875");
    public static TextBlock Text(string text, double size = 14, IBrush? color = null, bool bold = false) => new()
    {
        Text = text, FontSize = size, Foreground = color ?? Ink, FontWeight = bold ? FontWeight.SemiBold : FontWeight.Normal,
        TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center
    };
    public static Button Button(string label, Action action, bool primary = false)
    {
        var button = new Button { Content = label, Padding = new Thickness(14, 9), CornerRadius = new CornerRadius(7),
            Background = primary ? Purple : Brush.Parse("#F1EDF3"), Foreground = primary ? Brushes.White : Purple,
            HorizontalContentAlignment = HorizontalAlignment.Center, VerticalContentAlignment = VerticalAlignment.Center };
        button.Click += (_, _) => action(); return button;
    }
    public static Border Card(Control content, double padding = 18) => new()
    {
        Child = content, Padding = new Thickness(padding), Background = Brushes.White, CornerRadius = new CornerRadius(12),
        BorderBrush = Brush.Parse("#E8E0EB"), BorderThickness = new Thickness(1)
    };
    public static TextBox Input(string value = "", string? placeholder = null) => new()
    {
        Text = value, Watermark = placeholder, Padding = new Thickness(10, 8), HorizontalAlignment = HorizontalAlignment.Stretch,
        VerticalContentAlignment = VerticalAlignment.Center, CornerRadius = new CornerRadius(6)
    };
    public static StackPanel Column(params Control[] children)
    {
        var panel = new StackPanel { Spacing = 12 }; foreach (var child in children) panel.Children.Add(child); return panel;
    }
    public static Grid Row(string columns, params Control[] children)
    {
        var grid = new Grid { ColumnDefinitions = ColumnDefinitions.Parse(columns), ColumnSpacing = 10 };
        for (var i = 0; i < children.Length; i++) { Grid.SetColumn(children[i], i); grid.Children.Add(children[i]); }
        return grid;
    }
    public static Control Field(string label, Control input) => Column(Text(label, 12, Muted, true), input);
    public static Window Dialog(string title, double width = 600) => new()
    {
        Title = title, Width = width, MinWidth = 420, Height = 650, MinHeight = 400, MaxHeight = 850,
        WindowStartupLocation = WindowStartupLocation.CenterOwner, Background = Brush.Parse("#F7F4F8"),
        FontFamily = new FontFamily("Segoe UI, Microsoft YaHei UI, PingFang SC"), FontSize = 14
    };
    public static async Task<bool> Confirm(Window owner, string title, string message, string yes, string no)
    {
        var dialog = Dialog(title, 500); dialog.Height = 270;
        dialog.Content = new ScrollViewer { Content = new StackPanel { Margin = new Thickness(24), Spacing = 22,
            Children = { Text(title, 21, Purple, true), Text(message), Row("*,*", Button(no, () => dialog.Close(false)), Button(yes, () => dialog.Close(true), true)) } } };
        return await dialog.ShowDialog<bool>(owner);
    }
}
