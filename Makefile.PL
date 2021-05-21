use inc::Module::Install; 

name 'bss';
version '0.1';

requires 'Config::IniFiles';
requires 'Template::Toolkit';
requires 'Text::Markdown';
requires 'YAML';

auto_install;
WriteAll;

