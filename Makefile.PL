use inc::Module::Install; 

name 'bss';
version '0.1';

requires 'Config::IniFiles';
requires 'DateTime';
requires 'Template::Toolkit';
requires 'Template::Plugin::Markdown';
requires 'Text::Markdown';
requires 'YAML';

auto_install;
WriteAll;

