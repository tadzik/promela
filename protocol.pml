mtype = { MSG, ACK };
#define S1_Request 0
#define S2_Acceptance 1
#define S3_Control 2
#define S4_Ack 3
#define S5_Rejection 4
#define S6_Close_Session 5
#define S7_End 6
#define S8_Cancelled 7
#define Inna14 8

#define REASON_TOOMANY 0

typedef proto {
    bit id[3];
};

typedef header {
    byte first;
    byte second;
}

typedef data {
    bit buf[256];
}

chan do_robotow = [1] of { mtype, bit, proto, byte, header, data };
chan do_bazy    = [1] of { mtype, bit, proto, byte, header, data };

bit activeSessions[16];

inline newSessionId() {
    int i;
    for (i : 0..15) {
        if
        :: (activeSessions[i] == 0) ->
            head.second = i;
            activeSessions[i] = 1;
            goto SUCCESS;
        :: (activeSessions[i] == 1) -> skip
        fi
    }
    goto FAIL;
SUCCESS:
    do_robotow ! MSG (false, protocol, S5_Rejection, head, buf);
    goto END;
FAIL:
    head.second = REASON_TOOMANY;
    do_robotow ! MSG (0, protocol, S5_Rejection, head, buf);
    goto KONIEC_BAZY;
END:
}

active proctype Baza() {
    bit ack;
    proto protocol;
    byte msgid;
    header head;
    data buf;

    do_bazy ? MSG (ack, protocol, S1_Request, head, buf);
    newSessionId();
    do
        :: do_robotow ! MSG (0, protocol, S3_Control, head, buf) ->
            printf("Wysylam control, czekam na ack\n");
            do_bazy ? MSG (ack, protocol, S4_Ack, head, buf);
            printf("Dostalem ack\n");
    od;
KONIEC_BAZY:
}

active proctype Robot() {
    bit ack;
    proto protocol;
    int sessionid;
    byte msgid;
    header head;
    data buf;
    head.first = 1;

    atomic {
        do_bazy ! MSG (0, protocol, S1_Request, head, buf);
        do_robotow ? MSG (ack, protocol, msgid, head, buf) ->
        printf("Przydzielone sessionid: %d\n", head.second);
    }
    do
        :: do_robotow ? MSG (ack, protocol, S3_Control, head, buf) ->
            printf("Dostalem control, odsylam ack\n");
            do_bazy ! MSG (ack, protocol, S4_Ack, head, buf);
        :: timeout ->
            printf("Robot idle\n");
    od
}
