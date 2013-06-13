for (1..100) {
    if (system("spin protocol.pml") != 0) {
        print "Fuckup\n";
        return;
    }
}

print "Wygląda na to, że się nie wywala\n";
