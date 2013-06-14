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


typedef header {
    byte first;
    byte second;
}


chan do_robotow = [1] of { mtype, bit, byte, header};
chan do_bazy    = [1] of { mtype, bit, byte, header};

chan do_robotow_proxy = [1] of { mtype, bit, byte, header};
chan do_bazy_proxy    = [1] of { mtype, bit, byte, header};

bit activeSessions[2];

inline newSessionId() {
    int i;
    for (i : 0..1) {
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
    do_robotow_proxy ! MSG (false, S2_Acceptance, head);
    goto END;
FAIL:
    head.second = REASON_TOOMANY;
    if 
        :: do_robotow_proxy ! MSG (0, S5_Rejection, head);
        :: timeout -> assert(0);
    fi;
    goto KONIEC_BAZY;
END:
}

inline closeSession() {
    printf("Baza otrzymuje S6, zamykamy interes\n");
    if 
        :: do_robotow_proxy ! MSG (0, S7_End, head);
        :: timeout -> assert(0);
    fi;
    goto KONIEC_BAZY;
}

active proctype Baza() {
    bit ack;
    byte msgid;
    header head;
    do_bazy ? MSG (ack,  S1_Request, head);
    newSessionId();
    printf("Baza wchodzi w pętlę główną\n");
    do
        :: do_bazy ? MSG (0, S6_Close_Session, head) ->
            closeSession();
        :: do_robotow_proxy ! MSG (0, S3_Control, head) ->
            printf("Wysylam control, czekam na ack\n");
            if
                :: do_bazy ? MSG (ack, S4_Ack, head);
                    printf("Dostalem ack\n");
                :: do_bazy ? MSG (0, S6_Close_Session, head);
                    printf("Zamiast ack dostałem close session. Ok.\n");
                    closeSession();
                :: timeout -> 
                    printf("Problemy z połączeniem - baza\n");
                    if
                        :: do_bazy ? MSG (ack,  S3_Control, head) -> 
                            skip;
                            printf("Odzyskano połączenie - baza\n");
                        :: timeout ->
                            printf("Utracono połączenie - baza\n");
                    fi;
            fi;
        :: do_robotow_proxy ! MSG (0, S8_Cancelled, head) ->
            printf("Wysylam cancelled, zwijamy interes\n");
            if 
                :: do_robotow_proxy ! MSG (0, S7_End, head);
                :: timeout -> skip;
            fi;
            goto KONIEC_BAZY;
    od;
KONIEC_BAZY:
}

active proctype Robot() {
    bit ack;
    int sessionid;
    byte msgid;
    header head;
    head.first = 1;

    atomic {
        do_bazy_proxy ! MSG (0, S1_Request, head);
        do_robotow ? MSG (ack, msgid, head);
        if 
            :: (msgid == S2_Acceptance) ->
                printf("Przydzielone sessionid: %d\n", head.second);;
            :: (msgid == S5_Rejection) ->
                printf("Zapytanie o sesję odrzucone");
                goto KONIEC_ROBOTA;
            :: else ->
                assert(0);
        fi
    }
    do
        :: do_robotow ? MSG (ack, S3_Control, head) ->
            printf("Dostalem control, odsylam ack\n");
            do_bazy_proxy ! MSG (ack, S4_Ack, head);
	:: do_robotow ? MSG (ack, S2_Acceptance, head) ->assert(0);
	:: do_robotow ? MSG (ack, S5_Rejection, head) ->assert(0);
	:: do_robotow ? MSG (ack, S7_End, head) ->assert(0);
        :: do_robotow ? MSG (ack, S8_Cancelled, head);
            printf("Robot otrzymal canceled\n");
            do_bazy_proxy ! MSG (0, S7_End, head);
            goto KONIEC_ROBOTA;
        :: do_bazy_proxy ! MSG (0, S6_Close_Session, head);
            printf("Robot wysyła close session\n");
            do
                :: do_robotow ? MSG (0, msgid, head);
                printf("Robot otrzymał msg: %d\n", msgid);
                // sometimes we get S8_Cancelled.
                // it happens whenever base sends this signal before it really receives S6_Close_Session 
                if
                    :: (msgid == S7_End) -> goto KONIEC_ROBOTA;
                    :: else skip;
                fi;

            od;
            goto KONIEC_ROBOTA;
        :: timeout -> 
            printf("Utracono połączenie - robot\n");
            break;
    od;
KONIEC_ROBOTA:
}

active proctype PerfectProxy() {
    bit ack;
    byte msgid;
    header head;
    do
        :: do_robotow_proxy ? MSG (ack, msgid, head) ->
            do_robotow ! MSG (ack, msgid, head);
        :: do_bazy_proxy ? MSG (ack, msgid, head) ->
            do_bazy ! MSG (ack, msgid, head);
    od
}

proctype Proxy() {
    bit ack;
    byte msgid;
    header head;
    do
        :: do_robotow_proxy ? MSG (ack, msgid, head) ->
        if
            :: do_robotow ! MSG (ack, msgid, head);
            :: skip;
        fi
        :: do_bazy_proxy ? ACK (ack, msgid, head) ->
        if
            :: do_bazy ! ACK (ack, msgid, head);
            :: skip
        fi
    od
}
