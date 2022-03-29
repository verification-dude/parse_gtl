<'
import parse_tfile.e;

extend gtl_parser {
    // remove timing checks while keeping the rest (RECREM, WIDTH etc.)
    take_action(path: string) is {
        files.write(tfile,append("PATH ",path," $setup $hold $setuphold -tcheck"));
    };
}; -- extend gtl_parser

extend sys {
    gtl_parser: gtl_parser;
    run() is also {
        // main parse call
        gtl_parser.gtl_parse("gtl/design_top.v","design_top.tfile");

        // flattened synchonizer search		
        gtl_parser.dfs(gtl_parser.root,{"..._first_inst_name_..."},"TOP_TB.top_inst");
        // synchronizer with hierarchy search
        gtl_parser.dfs(gtl_parser.root,{"...first_inst_name";"...sub_inst_name"},"TOP_TB.top_inst");
        // close result file
        files.flush(gtl_parser.tfile);
    };
};

'>