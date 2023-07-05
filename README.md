# ADCC
Progetto Applicazioni Distribuite e Cloud Computing


1. Introduzione
Nell'ambito dello sviluppo di sistemi distribuiti e concorrenti, uno dei linguaggi di programmazione più potenti ed efficienti è Erlang. Questo è infatti caratterizzato da una sintassi funzionale e basata su attori che lo rende ideale per la realizzazione di applicazioni scalabili e basati sulla concorrenzialità.
In questa realizzazione affronteremo la prima opzione tra i progetti consigliati, ovvero l’implementazione di uno spazio di Tuple utilizzando il linguaggio di programmazione Erlang. Per spazio di Tuple si intende una struttura dati condivisa in grado far accedere ai propri dati in maniera concorrenziale più processi contemporaneamente. Questi saranno in grado di scrivere, leggere e cancellare i vari pattern all’interno dello spazio.
Lo scopo di questo progetto è quello di sviluppare un sistema in grado di gestire l'accesso concorrente alle Tuple, garantendo l'atomicità delle operazioni e la sincronizzazione tra i processi. Attraverso l'utilizzo di Erlang, sfrutteremo le sue caratteristiche intrinseche per realizzare un'implementazione efficiente ed ordinata dello spazio di Tuple concorrenziale.
All’interno della relazione esploreremo il linguaggio di programmazione Erlang con le sue caratteristiche principali, descriveremo l’architettura del sistema evidenziando le scelte progettuali e le strutture dati utilizzate per garantire la correttezza e l’efficienza delle operazioni sullo spazio di Tuple.
Lo sviluppo del progetto avverrà interamente in ambiente di test virtualizzato su sistema operativo Windows. In esso verrà simulato l’avvio di più nodi locali che, una volta lanciati, effettueranno il collegamento tra loro per poi accedere in modo uniforme su un unico database su cui appoggerà il TS (Tuple Space).
2. Primo approccio ad Erlang come linguaggio di sviluppo
Erlang è un linguaggio di programmazione ottimizzato per lo sviluppo di sistemi concorrenti e distribuiti ad alta affidabilità. Con il suo modello di concorrenza basato sugli attori e le sue caratteristiche di gestione degli errori e di programmazione distribuita , Erlang offre un approccio unico per affrontare le sfide della programmazione parallela.
Il primo passo è comprenderne le caratteristiche fondamentali. Erlang adotta una sintassi funzionale, che incoraggio l'uso di funzioni pure evitandone gli effetti collaterali. Questo ci aiuta ad avere una programmazione più chiara e leggibile facilitando la comprensione e la manutenzione del codice.
Come detto precedentemente, ogni processo è isolato dagli altri e comunica solo attraverso il passaggio di messaggi, questo modello rende più semplice la concorrenza, per poter sfruttare appieno anche le caratteristiche dei nuovi processori multicore, capaci di lanciare e gestire più thread contemporaneamente.
Un altro punto di forza di Erlang è la sua gestione integrata degli errori. Erlang è stato progettato per applicazioni in cui l'affidabilità è fondamentale. Offre meccanismi per gestire gli errori in modo controllato e per recuperare situazioni di errore senza interrompere l'esecuzione del sistema. Questo approccio garantisce un'elevata resilienza e tolleranza ai guasti, che sono fondamentali per applicazioni critiche e ad alta disponibilità.
Oltre a questo, offre un supporto nativo per la programmazione distribuita. Con semplici meccanismi, è possibile creare, controllare e comunicare tra processi distribuiti su diverse macchine. Questa capacità consente lo sviluppo di sistemi scalabili e distribuiti, in cui i processi possono essere eseguiti su nodi diversi della rete e comunicare in modo trasparente.
3. Sviluppo del progetto
Il Tuple space è stato sviluppato tramite un’ applicazione principale di Erlang chiamata TS che si occuperà di lanciare
a. Cosa è uno spazio di Tuple
Uno spazio di Tuple, noto anche come Tuple space (TS), è una struttura dati concorrente che permette a processi o thread di comunicare e condividere informazioni in modo asincrono. Possiamo descriverla come un'astrazione di memoria condivisa. Viene spesso fatta un analogia con una lavagna (black-board)in quanto è praticamente uno spazio dove tutti possono leggere e scrivere Tuple, ovvero, collezioni ordinate di elementi, all'interno di uno spazio condiviso.
Nello spazio di Tuple, i dati possono essere scritti da un processo in una posizione specifica e letti da altri processi in modo concorrente. Questo meccanismo facilita la cooperazione tra processi o thread che lavorano indipendentemente, consentendo loro di condividere dati senza dover interagire direttamente o condividere strutture dati complesse.
b. Descrizione delle caratteristiche e delle funzionalità di uno spazio di Tuple
Le operazioni principali che andremo ad integrare nel nostro progetto saranno quelle richieste nelle specifiche e anche quelle principali per l'interazione con un TS, ovvero:
- new(name) : crea un nuovo spazio di Tuple
- out(TS, Tuple) : metodo per inserire una Tuple "Tuple" all'interno dello spazio di Tuple
- rd(TS, Pattern) : metodo che estrapolerà e ci mostrerà un determinato match presente all'interno dello spazio di Tuple richiesto con il pattern specificato
- in(TS, Pattern) : metodo che estrapolerà e rimuoverà definitivamente dallo spazio di Tuple specificato il pattern matching richiesto.
Oltre questi implementeremo operazioni di Read e In con un ulteriore valore di Timeout per evitare situazioni di Deadlock.
- rd(TS, Pattern, Timeout) : in caso di pattern matching trovato la risposta sarà {ok, Tuple} altrimenti riceveremo un errore {err, Timeout}
- in(TS, Pattern, Timeout) : in caso di pattern matching trovato la risposta sarà {ok, Tuple} altrimenti riceveremo un errore {err, Timeout}
c. Operazioni sui nodi del sistema
In aggiunta alle operazioni basilari sugli spazi di Tuple andremo ad integrare anche le operazioni necessarie per connettere e rimuovere i nodi del sistema ad esse.
- addNodes(TS, Node) : aggiunge il nodo allo spazio di Tuple in modo che possa accedere ai dati, inserirli e rimuoverli.
- removeNode(TS, Node) : rimuove il nodo dallo spazio di Tuple
- nodes(TS) : ci dà un elenco dei nodi connessi allo spazio di Tuple specificato
4. Creazione dell’ambiente
Il sistema operativo su cui ho configurato l’ambiente di sviluppo del progetto è Windows 11, qui Erlang è disponibile come pacchetto precompilato semplificandone l’installazione e l’avvio del linguaggio. Questo comprende l’Erlang/OTP (Open Telecom Platform) che include il compilatore, il runtime e installa le librerie standard nel nostro pc.
Per quanto riguarda l’editor ho utilizzato il classico notepad++ .
Una cosa molto importante da fare è l’aggiunta del percorso dell’eseguibile di Erlang nell’ambiente di sviluppo di Windows per fare in modo di avviare i singoli nodi dalla shell del pc con un singolo comando.
 werl -sname stefano@localhost
Questo comando ci avvia una finestra separata di erlang, creando un nodo locale con nome (short) stefano@localhost
Questa parte è fondamentale in quanto durante i test tutti i nodi utilizzati per eseguire le prove sono locali all’interno della macchina. Una volta avviati tutti i nodi necessari sarà nostra premura stabilire un collegamento tra loro con il comando :
 net_adm:ping(stefano@localhost).
Stabilita una connessione tra i nodi sarà necessario, al primo avvio, compilare i singoli file inclusi nel progetto attraverso il comando c(file). :
 c(ts).
Compilati tutti i file e stabilita una connessione tra i singoli nodi sarà possibile iniziare ad interagire con il nostro Tuple Space
5. Scelte progettuali
Il progetto è composto da 5 file con estensione .erl
Il file principale ts.erl ha il compito di avviare con un unico comando tutto l’applicativo compreso il supervisor principale del progetto, main_supervisor. Questo è il processo padre di tutto il progetto, si occupa di garantire la costante e corretta esecuzione dei processi figli anche i caso di errore. Tra le tipologie del supervisor ho optato per quella one_for_one
Se un processo figlio termina solo quel processo viene riavviato
Quasi tutti i processi lanciati sfruttano il behaviour gen_server, fornito dalla libreria standard di Erlang. Questo fondamentale per la gestione delle relazioni client-server su sistemi concorrenziali e per integrare un set di funzioni di controllo dei processi e gestione degli errori automatizzata.
Come appena accennato quindi:
- ts contiene al suo interno il processo incaricato ad avviare tutti i figli (supervisor compresi) è: ts:start()
- main_supervisor è il supervisor principale che avvia come suoi figli i processi database_mgr e ts_supervisor
- ts_supervisor si occupa di implementare un supervisor che gestirà il corretto funzionamento dei processi del ts_mgr.
- ts_mgr si occupa della gestione dei dati all’interno di ogni Tuple Space, dalla scrittura dei dati all’eliminazione passando per la semplice consultazione
- database_mgr si occupa della gestione del database e quindi sincronizza quest’ultimo tra i diversi nodi, il collegamento e la rimozione di questi.
Il database locale di Erlang (mnesia) è un archivio distribuito in cui ogni nodo stabilisce una sua connessione al database. In fase di creazione di un nuovo Tuple Space, all’interno del database viene creata una nuova tabella con il nome del TS e viene lanciato il relativo processo locale di ts_mgr.
Attraverso il comando > observe:start() possiamo consultare i processi lanciati da ogni nodo e le tabelle del database, qui possiamo consultare anche i nodi collegati ad ogni spazio di tuple.
