#include <string>
#include <sstream>
#include <iostream>
#include "uci.h"
#include "misc.h"

using namespace Stockfish;

extern "C" const char* pf_bestmove(const char* fen, int movetime_ms) {
    static std::string result = "NONE";
    std::string input;
    input += "setoption name EvalFile value /var/mobile/xiangqiassist/pikafish.nnue\n";
    input += "position fen " + std::string(fen) + " - - 0 1\n";
    input += "go movetime " + std::to_string(movetime_ms) + "\n";
    std::istringstream in(input);
    std::ostringstream out;
    std::streambuf* oldCin = std::cin.rdbuf(in.rdbuf());
    std::streambuf* oldCout = std::cout.rdbuf(out.rdbuf());
    CommandLine cli;
    UCIEngine engine(cli);
    engine.loop();
    std::cin.rdbuf(oldCin);
    std::cout.rdbuf(oldCout);
    std::string s = out.str();
    size_t p = s.find("bestmove ");
    if (p != std::string::npos) {
        p += 9;
        int i = 0;
        while (p + i < s.length() && s[p+i] != ' ' && s[p+i] != '\n' && i < 5) i++;
        result = s.substr(p, i);
    }
    return result.c_str();
}
