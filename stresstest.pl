for (1..100) {
    if (system("spin protocol.pml") != 0) {
        print "Wywalił síę\n";
        exit 1;
    }
}

print "Wygląda na to, że się nie wywala\n";
