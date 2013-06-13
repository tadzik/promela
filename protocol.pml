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
    do_robotow ! MSG (false, S5_Rejection, head);
    goto END;
FAIL:
    head.second = REASON_TOOMANY;
    do_robotow ! MSG (0, S5_Rejection, head);
    goto KONIEC_BAZY;
END:
}

inline closeSession() {
    printf("Baza otrzymuje S6, zamykamy interes\n");
    do_robotow ! MSG (0, S7_End, head);
    goto KONIEC_BAZY;
}

active proctype Baza() {
    bit ack;
    byte msgid;
    header head;
    if
        :: do_bazy ? MSG (ack,  S1_Request, head) -> skip;
        :: timeout ->
	    printf("Problemy z połączeniem - baza\n");
	    if
	        :: do_bazy ? MSG (ack,  S1_Request, head) ->
	           skip;
	           printf("Odzyskano połączenie - baza\n");
	        :: timeout ->
	           printf("Utracono połączenie - baza\n");
	    fi;
    fi;
    newSessionId();
    printf("Baza wchodzi w pętlę główną\n");
    do
        :: do_bazy ? MSG (0, S6_Close_Session, head) ->
            closeSession();
        :: do_robotow ! MSG (0, S3_Control, head) ->
            printf("Wysylam control, czekam na ack\n");
            if
                :: do_bazy ? MSG (ack, S4_Ack, head);
                    printf("Dostalem ack\n");
                :: do_bazy ? MSG (0, S6_Close_Session, head);
                    printf("Zamiast ack dostałem close session. Ok.\n");
                    closeSession();
            fi;
        :: do_robotow ! MSG (0, S8_Cancelled, head) ->
            printf("Wysylam cancelled, zwijamy interes\n");
            do_robotow ! MSG (0, S7_End, head);
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
        do_bazy ! MSG (0, S1_Request, head);
        do_robotow ? MSG (ack, msgid, head) ->
        printf("Przydzielone sessionid: %d\n", head.second);
    }
    do
        :: do_robotow ? MSG (ack, S3_Control, head) ->
            printf("Dostalem control, odsylam ack\n");
            do_bazy ! MSG (ack, S4_Ack, head);
        :: do_robotow ? MSG (ack, S8_Cancelled, head);
            printf("Robot otrzymal canceled\n");
            do_bazy ! MSG (0, S7_End, head);
            goto KONIEC_ROBOTA;
        :: do_bazy ! MSG (0, S6_Close_Session, head);
            printf("Robot wysyła close session, czeka na S7\n");
            do
                :: do_robotow ? MSG (0, S7_End, head) ->
                    goto KONIEC_ROBOTA;
                :: else ->
                    do_robotow ? MSG (0, msgid, head);
                    printf("Wiadomosc inna niż S7, id: %d\n", msgid);
            od;
	:: timeout -> 
		printf("Utracono połączenie - robot\n");
		break;
    od;
KONIEC_ROBOTA:
}
