# Hitman Console

![](https://i.imgur.com/IqrIOI9.png)

La conectarea pe server ar trebui să vedeți mesajul:

> Hitman Console loaded successfully, use /hac to view more information.

Dacă vedeți mesajul de mai sus, înseamnă că totul este în regulă și modulul s-a încărcat cu succes.

Totodată, la conectarea pe server o să fiți informați în cazul în care există o versiune nouă a modului, și o veți putea descărca automat, din joc, fără să fiți nevoiți să vă reconectați.

Aveți la dispoziție comanda /hac, prin intermediul căreia puteți accesa meniul în care activați, dezactivați și modificați diverse opțiuni ale modulului.

![](https://i.imgur.com/20pPzx2.jpeg)

![](https://i.imgur.com/oYLcoE0.jpeg) ![](https://i.imgur.com/ifF5cAd.jpeg)

## Instalare

Copiați conținutul din hitman-console și îl amplasați în folderul MoonLoader.

Principiul este simplu: luați un contract ca de obicei:
- /turn off
- /gethit
- /mycontract - aici se va seta automat checkpoint-ul pe țintă și veți vedea suma contractului în consolă
- /undercover

![](https://i.imgur.com/qQzJVkT.png) ![](https://i.imgur.com/EUV8WDB.png)

Pentru comoditate, există și câteva scurtături pentru comenzile folosite des: /ghit în loc de /gethit, /myc în loc de /mycontract, /under în loc de /undercover și /o1 în loc de /order 1.

Când consola este activă, aveți la dispoziție două butoane: Stay și Get Out, care trimit automat un mesaj pe /f sau pe /hi cu numele țintei, ID-ul acesteia și numărul de telefon. Din meniul /hac puteți selecta pe care chat doriți să se trimită mesajele. Butoanele devin active atunci când apăsați tasta Y — cursorul va apărea pe ecran și veți putea apăsa pe ele.

Pentru cei ce vor să ajute alți agenți, aveți la dispoziție și comenzi rapide pentru a trimite mesaje jucătorilor:
- /iesi, /getout
- /stai, /stay

Aceste comenzi trimit mesaje aleatorii către ținte. Mesajele pot fi modificate/adăugate din fișierul hitman_console.json (din folderul moonloader); inițial sunt câte 2 mesaje per acțiune. În cazul în care ținta nu are un număr de telefon, primiți un mesaj informativ.

Veți avea la dispoziție întreaga consolă cu informațiile afișate. Opțiunile vizibile pot fi ascunse din meniul /hac dacă considerați că interfața este prea încărcată. Tot din meniul /hac puteți modifica culoarea consolei și opacitatea acesteia, astfel încât să vă personalizați modulul după preferințe.

Consola afișează diverse informații care vă pot fi utile. Dacă nu aveți nevoie de anumite elemente, le puteți ascunde. Toate setările sunt salvate și vor rămâne active și după relogare.

În meniul /hac aveți și o secțiune de statistici, unde puteți vedea:
- numărul contractelor efectuate
- suma totală câștigată din contracte
- numărul contractelor eșuate
- numărul contractelor finalizate cu succes

În categoria Target din consolă sunt afișate diferite informații despre jucător. Atunci când acesta se află suficient de aproape (de-obicei <= 200m, pot fi și 700m, însă doar în cazurile când hitmanul/ținta se află la o înălțime mai mare/mică), vor fi disponibile mai multe date.

Skin-ul țintei este afișat lângă consolă. Atunci când puneți ținta, sub skin apare o bară care vă arată dacă ținta sniper-ului se află pe jucător (ON TARGET) sau nu (OFF TARGET). Tot legat de sniper, în categoria Hitman Console, sub statutul contractului, este afișat și numărul de gloanțe rămase la sniper.

La finalizarea contractului, checkpoint-ul și consola se vor ascunde automat după 10 secunde, dacă această opțiune este activată. Dacă doar consola se ascunde automat, checkpoint-ul va rămâne activ pentru ca să nu dispară instant, ca să reușiți să faceți screenshot după ce ținta este doborâtă.

În partea de jos a ecranului este afișat un timer care vă arată câte secunde mai aveți până puteți lua un contract, în cazul în care tocmai v-ați conectat pe server. În cazurile în care ați finalizat/anulat un contract, vă scrie ora și minutul la care veți putea primi un alt contract, iar când rămâne mai puțin de 60 de secunde, deja arată numărul de secunde. Timpul este calculat în timp real, așa că rămâne corect chiar dacă stați AFK. După ce pauza s-a încheiat, timer-ul se mai afișează încă maximum două minute, apoi dispare singur. Afișarea lui poate fi pornită sau oprită din meniul /hac.

Există un caz special la /cancelhit: dacă ținta se afla într-un interior, serverul de obicei nu vă mai pune pauză (cooldown de 0 secunde), însă acest lucru nu poate fi știut cu certitudine din cauza ultimelor modificări pe server. De aceea, după /cancelhit nu se pornește direct timer-ul, ci primiți un mesaj prin care modul vă sugerează să încercați să luați un contract — este posibil ca ținta să fi fost într-un interior. Dacă totuși serverul vă răspunde că trebuie să așteptați, atunci se pornește timer-ul numărând din momentul în care ați dat /cancelhit, nu din momentul în care ați văzut mesajul.

---

În cazul în care depistați anumite bug-uri, raportați-le și voi încerca să le rezolv cât mai rapid posibil, în dependență de timpul meu liber.

În cazul în care aveți alte idei, scrieți mai jos - orice poate fi folositor și, dacă ne permit regulile, posibil să fie implementat.

Beta testeri: [SEKIZ](https://bluepanel.bugged.ro/profile/670645), [Craita](https://bluepanel.bugged.ro/profile/840296) - mulțumesc pentru ajutor.

Mult succes la efectuarea contractelor!

---

Nu uitați: în joc veți fi notificați la fiecare conectare și pe parcurs atunci când este disponibilă o versiune nouă.
