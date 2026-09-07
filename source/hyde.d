module hyde;

enum hydeVersion = "0.0.0";

import std.json : JSONValue, JSONType, parseJSON, JSONOptions;
import std.algorithm.searching : canFind;
import std.string : split;
import std.path : isAbsolute;
import std.conv : to;
import std.stdio : stdout;

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

private void printHelp()
{
	stdout.writeln(`   /|     }/>          __ _dhyyy#%%\                __`);
	stdout.writeln(`  |%&     | y&;     &;/^</Y&&#%   %YY|   Y&dd#%=$=/|Y`);
	stdout.writeln(`  ;&%    ;&  \Y_   |#&;   {%/      \#\ <y##//      7`);
	stdout.writeln(`  :%___=%&|   \D__y#;    {%%        |D  |;/h\_`);
	stdout.writeln(`<=%%#?^&#HY    |h%&;:     |%      |E   /&|&/%#?&?:;|`);
	stdout.writeln(` /%/    H%/      y/      |%y    /%/    \%/        \|`);
	stdout.writeln(` ||     |E      /#y       ||H%/y      /%%`);
	stdout.writeln(`;/       %/   /D}        |%D/y       _|%&$%&%##|Yh\`);
	stdout.writeln(`             y^         <y/          y/          y&`);
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
	foreach (field; ["source", "output"])
	{
		validateRelative("posts/index.html", field "test");
		foreach (path; [""], "/index.html", `posts\index.html` , "./index.html", "posts/../index.html", "posts//index.html", "index.html\0ignored"])
		{
			asserThrown!Exception(validateRelative(path, field, "test"));
		}
	}
}