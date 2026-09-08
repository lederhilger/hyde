module hyde;

enum hydeVersion = "0.0.0";

import std.json : JSONValue, JSONType, parseJSON, JSONOptions;
import std.algorithm.searching : canFind, endsWith, startsWith;
import std.string : split, indexOf, toStringz, fromStringz;
import std.path : isAbsolute, buildPath, absolutePath;
import core.sys.posix.stdlib : realpath;
import std.conv : to;
import std.stdio : stdout;
import std.array : appender;
import core.stdc.stdlib : free;
import std.file : isDir, exists, isSymlink, readText, isFile;

private struct Page
{
	string title;
	string source;
	string output;
	string layout;
	string section;
}

private struct Site
{
	string title;
	string description;
	Page[] pages;
}

private struct Output
{
	string path;
	ubyte[] data;
}

private void rejectUnknown(const JSONValue[string] object, const string[] allowed, string name)
{
	foreach (field, value; object)
	{
		if (!allowed.canFind(field)) {throw new Exception(name ~ ": unknown field '" ~ field ~ "'");}
	}
}

private string requiredString( ref JSONValue[string] object, string field, string name, bool allowEmpty = false)
{
	auto value = field in object;
	if (value is null || value.type != JSONType.string) {throw new Exception(name ~ ": '" ~ field ~ "' must be a string");}
	if (!allowEmpty && value.str.length == 0) {throw new Exception(name ~ ": '" ~ field ~ "' must not be empty");}
	return value.str;
}

private void validateRelative(string path, string field, string name)
{
	if (path.length == 0 || isAbsolute(path) || path.canFind('\\') || path.canFind('\0'))
	{
		throw new Exception(name ~": '" ~ field ~ "' must be a safe relative path");
	}
	foreach (part; path.split('/'))
	{
		if (part.length == 0 || part == "." || part == "..")
		{
			throw new Exception(name ~ ": '" ~ field ~ "' must be a safe relative path");
		}
	}
}

/// Needs some fixing.
private void validateSection(string section, string name)
{
	switch (section)
	{
		case "":
		case "cv":
		case "weblog":
		case "projects":
		case "teaching":
		{
			return;
		}
		default:
		{
			throw new Exception(name ~ ": invalid section '" ~ section ~ "'");
		}
	}
}

private Site parseSite(string source, string name)
{
	JSONValue document;
	try
	{
		document = parseJSON(source, JSONOptions.strictParsing);
	}
	catch (Exception error)
	{
		throw new Exception(name ~ ": invalid JSON: " ~ error.msg);	
	}
	if (document.type != JSONType.object)
	{
		throw new Exception(name ~ ": expected object");
	}
	auto object = document.object;
	rejectUnknown(object, ["title", "description", "pages"], name);

	Site site;
	site.title = requiredString(object, "title", name);
	site.description = requiredString(object, "description", name);
	auto pages = "pages" in object;
	if (pages is null || pages.type != JSONType.array || pages.array.length == 0)
	{
		throw new Exception(name ~ ": 'pages' must be nonempty array");
	}

	foreach (index, value; pages.array)
	{
		string pageName = name ~ ": pages[" ~ index.to!string ~ "]";
		if (value.type != JSONType.object) {throw new Exception(pageName ~ " must be object");}
		auto pageObject = value.object;
		rejectUnknown(pageObject, ["title", "source", "output", "layout", "section"], pageName);

		Page page;
		page.title = requiredString(pageObject, "title", pageName);
		page.source = requiredString(pageObject, "source", pageName);
		page.output = requiredString(pageObject, "output", pageName);
		page.layout = requiredString(pageObject, "layout", pageName);
		page.section = requiredString(pageObject, "section", pageName, true);
		validateRelative(page.source, "source", pageName);
		validateRelative(page.output, "output", pageName);
		validateRelative(page.layout, "layout", pageName);
		if (page.layout.canFind('/')) {throw new Exception(pageName ~ ": 'layout' must be a name");}
		validateSection(page.section, pageName);
		site.pages ~= page;
	}
	return site;
}

private string navigation(string section)
{
	static immutable links = [
	       ["cv", "CV"],
	       ["weblog", "WEBLOG"],
	       ["projects", "PROJECTS"],
	       ["teaching", "TEACHING"]
	];

	auto result = appender!string;
	result.put("<nav aria-label=\"Primary navigation\">\n  <ul>\n");
	foreach (link; links)
	{
		result.put("    <li><a href=\"/");
		result.put(link[0]);
		result.put("/\" class=\"");
		if (section == link[0]) {result.put("is-active");}
		result.put("\">");
		result.put(link[1]);
		result.put("</a></li>\n");
	}
	result.put("  </ul>\n</nav>");
	return result.data;
}

private string render(string layout, const string[string] replacements, string name)
{
	enum marker = "$hyde{";
	auto result = appender!string;
	size_t cursor;
	size_t count;
	while (cursor < layout.length)
	{
		auto start = layout[cursor .. $].indexOf(marker);
		if (start < 0)
		{
			result.put(layout[cursor .. $]);
			break;
		}
		size_t status = cursor + cast(size_t) start;
		result.put(layout[cursor .. status]);
		size_t initus = status + marker.length;
		auto end = layout[initus .. $].indexOf('}');
		if (end < 0) {throw new Exception(name ~ ": unclosed placeholder");}
		size_t terminus = initus + cast(size_t) end;
		string nomen = layout[initus .. terminus];
		if (nomen == "content") {++count;}
		auto replacement = nomen in replacements;
		if (replacement is null)
		{
			throw new Exception(name ~ ": unknown placeholder '" ~ nomen ~ "'");
		}
		result.put(*replacement);
		cursor = terminus + 1;
	}
	if (count != 1)
	{
		throw new Exception(name ~ ": layout must contain exactly one $hyde{content}");
	}
	return result.data;
}

private string properPath(string path)
{
	auto resolved = realpath(path.toStringz, null);
	if (resolved is null)
	{
		throw new Exception("cannot resolve path: " ~ path);
	}
	scope (exit) {free(resolved);}
	return resolved.fromStringz.idup;
}

private string radix(string inputRoot)
{
	string root = absolutePath(inputRoot);
	if (!exists(root) || !isDir(root))
	{
		throw new Exception("site root not a directory: " ~ inputRoot);
	}
	return properPath(root);
}

private bool isWithin(string child, string parent)
{
	string prefix = parent.endsWith("/") ? parent : parent ~ "/";
	return child == parent || child.startsWith(prefix);
}

private string publicDirectory(string root)
{
	string output = buildPath(root, "public");
	if (exists(output) && isSymlink(output))
	{
		throw new Exception("refusing symlinked public directory: " ~ output);
	}
	if (exists(output))
	{
		if (!isDir(output))
		{
			throw new Exception("public not directory: " ~ output);
		}
		if (!isWithin(absolutePath(output), root))
		{
			throw new Exception("public outside root: " ~ output);
		}
	}
	else if (!isWithin(absolutePath(output), root))
	{
		throw new Exception("public outside root: " ~ output);
	}
	return output;
}

private string checkReadText(string path, string description)
{
	if (!exists(path) || !isFile(path))
	{
		throw new Exception("missing " ~ description ~ ": " ~ path);
	}
	try {return readText(path);}
	catch (Exception error)
	{
		throw new Exception("cannot read " ~ description ~ " '" ~ path ~ "': " ~ error.msg);
	}
}

private void claimPath(ref string[string] owners, string path, string owner)
{
	foreach (claimed, previousOwner; owners)
	{
		if (pathsConflict(path, claimed))
		{
			throw new Exception("collision between " ~ previousOwner ~ " and " ~ owner ~ ": " ~ path);
		}
	}
	owners[path] = owner;
}

private bool pathsConflict(string left, string right)
{
	return left == right || (left.length > right.length && left.startsWith(right) && left[right.length] == '/') || (right.length > left.length && right.startsWith(left) && right[left.length] == '/');
}

private string escapeHTML(string value)
{
	auto result = appender!string;
	foreach (character; value)
	{
		switch (character)
		{
			case '&': result.put("&amp;"); break;
			case '<': result.put("&lt;"); break;
			case '>': result.put("&gt;"); break;
			case '"': result.put("&quot;"); break;
			case '\'': result.put("&#39;"); break;
			default: result.put(character); break;
		}
	}
	return result.data;
}

void buildSite(string inputRoot)
{
	string root = radix(inputRoot);
	string outputDirectory = publicDirectory(root);
	string pagesDirectory = buildPath(root, "pages");
	string layoutsDirectory = buildPath(root, "layouts");
	string staticDirectory = buildPath(root, "static");
	foreach (path; [pagesDirectory, layoutsDirectory, staticDirectory])
	{
		if (!exists(path) || !isDir(path))
		{
			throw new Exception("missing directory: " ~ path);
		}
	}
	string configurePath = buildPath(root, "site.json");
	Site site = parseSite(checkReadText(configurePath, "site.json"), configurePath);

	Output[] files;
	string[string] owners;
	foreach (index, page; site.pages)
	{
		claimPath(owners, page.output, "pages[" ~ index.to!string ~ "]");
	}
	claimPath(owners, ".nojekyll", "hyde");

	foreach (page; site.pages)
	{
		string content = checkReadText(buildPath(pagesDirectory, page.source), "page source");
		string layoutPath = buildPath(layoutsDirectory, page.layout ~ ".html");
		string layout = checkReadText(layoutPath, "layout");
		string[string] replacements = [
			       "title": escapeHTML(page.title),
			       "site_title": escapeHTML(site.title),
			       "description": escapeHTML(site.description),
			       "content": content,
			       "navigation": navigation(page.section)
		];
		string html = render(layout, replacements, layoutPath);
		files ~= Output(page.output, cast(ubyte[]) html.dup);
	}
}

private void printHelp()
{
	stdout.writeln(`   /|     }/>          __ _dhyyy#%%\     Y&dd#%=$=/|Y`);
	stdout.writeln(`  |%&     | y&;     &;/^</Y&&#%   %YY| <y##//      7`);
	stdout.writeln(`  ;&%    ;&  \Y_   |#&;   {%/      \#\  |;/h\_`);
	stdout.writeln(`  :%___=%&|   \D__y#;    {%%        |D /&|&/%#?&?:;|`);
	stdout.writeln(`<=%%#?^&#HY    |h%&;:     |%      |E   \%/        \|`);
	stdout.writeln(` /%/    H%/      y/      |%y    /%/   /%%`);
	stdout.writeln(` ||     |E      /#y       ||H%/y     _|%&$%&%##|Yh\`);
	stdout.writeln(`;/       %/   /D}        |%D/y       y/          y&`);
	stdout.writeln(`             y^         <y/`);
	stdout.writeln();
	stdout.writeln("Using hyde:");
	stdout.writeln("  hyde build --site <path>");
	stdout.writeln("  hyde --help");
	stdout.writeln("  hyde --version");
}

int run(string[] arguments)
{
	if (arguments.length == 2 && arguments[1] == "--help")
	{
		printHelp();
		return 0;
	}
	if (arguments.length == 2 && arguments[1] == "--version")
	{
		stdout.writeln("hyDe ", hydeVersion);
		return 0;
	}
	return 2;
}

version (unittest)
{
	void main() {}
}
else
{
	int main(string[] arguments) {return run(arguments);}
}

unittest
{
	import std.exception : assertThrown;
	validateRelative("posts/index.html", "source", "test");
	foreach (path; ["", "/index.html", `posts\index.html` , "./index.html", "posts/../index.html", "posts//index.html", "index.html\0ignored"])
	{
		assertThrown!Exception(validateRelative(path, "output", "test"));
	}
	string[string] owners;
	claimPath(owners, "index.html", "first page");
	assertThrown!Exception(claimPath(owners, "index.html", "second page"));
}

unittest
{
	import std.exception : assertThrown;
	assert(escapeHTML(`<tag lorem="ipsum">Jekyll & 'Hyde'</tag>`) == "&lt;tag lorem=&quot;ipsum&quot;&gt;Jekyll &amp; &#39;Hyde&#39;&lt;/tag&gt;");
	assertThrown!Exception(parseSite(`{
		"title":"Dr. Jekyll & Mr. Hyde",
		"description": "The Strange Case",
		"pages":[{
			"title": "The Story of the Door",
			"source": "doorstory.html",
			"output": "doorstory.html",
			"layout": "default",
			"section": ""
		}],
		"unknown": true
	}`, "site.json"));
	assertThrown!Exception(parseSite(`{
		"title":"Dr. Jekyll & Mr. Hyde",
		"description": "The Strange Case",
		"pages":[{
			"title": "The Story of the Door",
			"source": "doorstory.html",
			"output": "doorstory.html",
			"layout": "default",
			"section": "",
			"unknown": true
		}]
	}`, "site.json"));
	const string[string] replacements = [
	      "title": "Dr. Jekyll",
	      "site_title": "$hyde{title}",
	      "description": "English doctor with an alter ego",
	      "content": "literal $hyde{missing}",
	      "navigation": "nav"
	];
	assert(render("$hyde{title}: $hyde{content}", replacements, "layout") == "Dr. Jekyll: literal $hyde{missing}");
	assert(render("$hyde{site_title}$hyde{content}", replacements, "layout") == "$hyde{title}literal $hyde{missing}");
	assertThrown!Exception(render("$hyde{content}$hyde{title", replacements, "layout"));
}