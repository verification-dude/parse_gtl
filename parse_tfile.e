<'
// this struct represents Verilog module. it has a list of "kids" sub modules with a list of their names
// this is done so the names can be different when the "kid" is the same. this way we can implement many 
// instantiations of the same module while each instance has a different name

// leaf kids is for modules that are defined in other files (such as library files). 
// they are represented only with their instance name 
// (changing tcheck on inner components of such modules should be done in the library itself - or by other tools)

struct module {
    name: string;
    kids: list of module;
    kids_names: list of string;
    leaf_kids: list of string;
};

// this module performs the file reading and parsing

struct gtl_parser {
    // holds pointer to top DUT module. 
    // if the design has more than one top - it should be added to the parsing method
    !root: module;
    
    // holds all the modules that are parsed during the file reading part. 
    // this list holds only the modules and not thier instantiations
    !module_list: list(key: name) of module;

    // gate level file handle
    !gtl_file: file;
    
    // output file handle
    !tfile: file;
    
    // current string read from file;
    !cur_line: string;
    
    // holds current line after cutting it to separate words
    !line_elements: list of string;
    
    // flag to note if multiple lines declaration is present (such as when module header
    // or module instntiation happens)
    !multiple_line_element: bool;

    // hook method for output file operation
    take_action(path: string) is empty;

    // match method for DFS string matching
    module_match(module_name: string, search_key: string): bool is {
        return module_name ~ search_key;
    }; -- module_match()

    // search method on file parse resulting tree
    // the search is done with DFS algorithm. it uses the list of search items and tries to find paths where
    // each item is matched. the matching can be acomplished with any number of hierarchies between matches
    // when running dfs - the path to top module should be given
    
    dfs(module: module,search_keys: list of string,current_path: string) is {
        for each in module.kids {
            if search_keys is empty {
                return;
            };
            // match is done with instance names and not instance type - hence, the use of kids_names[index] and not 
            // kids[index].name or it.name
            if module_match(module.kids_names[index],search_keys[0]) {
                if search_keys.size() == 1 { // last search term -> match
                    take_action(append(current_path,".",module.kids_names[index]));
                } else {
                    // recrosive search with 1 less search term
                    dfs(it,search_keys[1..],append(current_path,".",module.kids_names[index]));
                };
            } else {
                // no match - recorsive search on lower part of tree
                dfs(it,search_keys,append(current_path,".",module.kids_names[index]));          
            };
        };
        // only if search key size is 1 -> not looking into multiple hierarchies
        if search_keys.size() == 1 {
            // if leaf_kids match the search (libraty modules) - apply tcheck action on them
            for each in module.leaf_kids {
                if module_match(it,search_keys[0]) {
                    take_action(append(current_path,".",it));
                };
            };
        };
    }; -- dfs()
    
    // parse action for "module" lines - create new module struct
    handle_module_start(line_element: string) is {
        multiple_line_element = TRUE;
        module_list.add(new module with {
                        .name = line_element;
                        });
    };

    // when inside "(" parantheses - ignore all contents - no modules are defined here
    // so if nested parentheses, just skip the line
    // all parentheses are terminated by ";", so no need to keep track of parentheses level
    handle_parentheses(line_elements: list of string) is {
        // when inside "(" parantheses - ignore all contents - no modules are defined here
        if multiple_line_element {
            return;
        };
        multiple_line_element = TRUE;
        // only first parantheses inside module is when sub-module instantiation
        // there are 2 options - 
        // 1 - a module that was defined earlier in the file
        // 2 - a module that was defined in a library file

        // option 1
        if module_list.key(line_elements[0]) != NULL {
            // add pointer to module type
            module_list.top().kids.add(module_list.key(line_elements[0]));
            // add the name of the module instance
            module_list.top().kids_names.add(line_elements[1]);
        } else {
            // add name of library module instance
            module_list.top().leaf_kids.add(line_elements[1]);
        };
    };
    
    // toggle end of parentheses - resume search for modules
    handle_end_current_state() is {
        multiple_line_element = FALSE;        
    };

    parse_line(cur_line: string) is {
        line_elements = str_split(cur_line," ");
        // remove any start of line "" strings (from white spaces)
        while line_elements is not empty and line_elements[0] == "" {
            line_elements = line_elements[1..];
        }; 
        if line_elements is empty {
            return;
        };
        // there are three elemnts that are interesting
        // 1 - "module" declaration - module start - has to be first word in line
        // 2 - "(" that are not in "module" lines 
        // 3 ";" terminate module or instance lines (always searched)
        if line_elements[0] == "module" {
            handle_module_start(line_elements[1]);
        } else if line_elements.has (it ~ "...(...") {
            handle_parentheses (line_elements);
        };
        if line_elements.has (it ~ "...;...") {
            handle_end_current_state();
        };
    };
    
    gtl_parse(gtl_file_name: string,tfile_name: string) is {
        // for handling paths that contain "$"
        var divided_path: list of string = str_split(gtl_file_name,"/");
        // for progress printout
        var line_num: uint(bits:64);
        var total_line_num: uint(bits:64);
        var current_persentage: uint;

        // next lines are for opening the files for read and write
        if str_sub(divided_path[0],0,1) == "$" {
            divided_path[0] = output_from(append("echo ",divided_path[0]))[0];
        };
        gtl_file_name = str_join(divided_path,"/");

        gtl_file = files.open(gtl_file_name,"r","");
        
        total_line_num = str_split(output_from(append("wc ",gtl_file_name," -l"))[0]," ")[0].as_a(uint);
        
        divided_path = str_split(tfile_name,"/");
        if str_sub(divided_path[0],0,1) == "$" {
            divided_path[0] = output_from(append("echo ",divided_path[0]))[0];
        };
        tfile_name = str_join(divided_path,"/");

        gtl_file = files.open(gtl_file_name,"r","");
        tfile = files.open(tfile_name,"w","");

        // main look of the program
        while files.read(gtl_file,cur_line) {
            line_num+=1;
            if (line_num * 100) / total_line_num != current_persentage {
                current_persentage = (line_num * 100) / total_line_num;
                out("Parse percentage: ",dec(current_persentage),"%");
            };
            parse_line(cur_line);
        };
        // usually the last module defined in the file is the top module. 
        root = module_list.top();
    };
}; -- struct gtl_parser
'>

