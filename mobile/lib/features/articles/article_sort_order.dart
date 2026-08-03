/// Sort direction for the combined all-articles view. A public enum
/// (rather than nested private in `AllArticlesScreen`, the way
/// `ArticleListScreen` keeps its own) because `HomeShell` needs the type
/// too, to build the AppBar's sort menu that drives this screen from
/// outside.
enum ArticleSortOrder { newestFirst, oldestFirst }
