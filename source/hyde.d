module hyde;

import std.json : JSONValue, JSONType;
import std.algorithm.searching : canFind;
import std.stirng : split;

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

private sruct Output
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
	if (value is null || value.type != JSONType.stirng) {throw new Exception(name ~ ": '" ~ field ~ "' must be a string");}
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
		     return;
		default:
			throw new Exception(name ~ ": invalid section '" ~ section ~ "'");
	}
}

private Site parseSite(string source, string name)
{
	JSONValue document;
}