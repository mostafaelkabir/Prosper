import Foundation

public extension AdultDomains {
    /// List version. Lists only ever grow between versions: a new version is a
    /// union with the old one, never a removal (PLAN.md §3.2).
    static let macListVersion = 1

    /// Everything the Mac guard blocks by name: the shared list plus the long
    /// tail. Curated by hand for v1; M2.1 replaces the long tail with a large
    /// licensed list (OISD NSFW or StevenBlack) once that download is approved.
    static let mac: Set<String> = Set(builtIn + longTail)

    /// Host labels that mark a site as adult wherever they appear. Matched on
    /// whole DNS labels or label prefixes/suffixes (see `GuardMatcher`), never
    /// as a bare substring, so "essex.ac.uk" and "sextant.io" stay reachable.
    static let hostKeywords: [String] = [
        "porn", "xxx", "hentai", "nsfw", "xvideo", "xnxx", "xhamster", "redtube",
        "youporn", "brazzers", "camgirl", "camgirls", "sexcam", "sexcams",
        "livesex", "freesex", "sextube", "sexvideo", "sexvideos", "nudes",
        "onlyfans", "fansly", "milf", "bdsm", "fetish", "escort", "escorts",
        "camsoda", "rule34", "gelbooru", "erotic", "erotica", "nude",
    ]

    static let longTail: [String] = [
        // Tube and clip sites
        "redtube.com", "youporn.com", "tube8.com", "porn.com", "beeg.com", "eporner.com",
        "txxx.com", "hclips.com", "hdzog.com", "porntrex.com", "4tube.com", "porntube.com",
        "fuq.com", "drtuber.com", "sunporno.com", "tnaflix.com", "empflix.com", "slutload.com",
        "pornhd.com", "youjizz.com", "keezmovies.com", "extremetube.com", "spankwire.com",
        "thumbzilla.com", "ixxx.com", "alohatube.com", "anysex.com", "vjav.com", "jav.guru",
        "javhd.com", "javlibrary.com", "missav.com", "missav.ws", "supjav.com", "porn300.com",
        "pornone.com", "xbabe.com", "yourporn.sexy", "sxyprn.com", "daftsex.com", "fapster.xxx",
        "porngo.com", "pornhat.com", "okxxx1.com", "hqporner.com", "perfectgirls.net",
        "xxxbunker.com", "pornoxo.com", "nuvid.com", "gotporn.com", "pornerbros.com",
        "cliphunter.com", "befuck.com", "xozilla.com", "ok.xxx", "pornzog.com", "porndig.com",
        "voyeurhit.com", "xcafe.com", "porn7.xxx", "upornia.com", "manysex.com", "fapvid.com",
        "iceporn.com", "pornburst.xxx", "xxxdan.com", "noodlemagazine.com", "pornktube.com",
        "porndoe.com", "shooshtime.com", "vporn.com", "xmoviesforyou.com", "watchporn.to",
        "fullporner.com", "porntop.com", "pornwhite.com", "pornjam.com", "bellesa.co",
        "xxxfiles.com", "megatube.xxx", "xtube.com", "pornhubpremium.com", "xvideos.red",
        "xvideos2.com", "xvideos3.com", "xnxx.tv", "xhamster.desi", "xhamster2.com",
        "xhamsterlive.com", "pornhub.org", "pornhub.net",
        // Studios and paysites
        "brazzers.com", "realitykings.com", "bangbros.com", "naughtyamerica.com", "mofos.com",
        "digitalplayground.com", "vixen.com", "tushy.com", "blacked.com", "deeper.com",
        "evilangel.com", "kink.com", "teamskeet.com", "metart.com", "met-art.com",
        "hegre.com", "x-art.com", "playboy.com", "playboyplus.com", "penthouse.com",
        "hustler.com", "private.com", "21sextury.com", "julesjordan.com", "babes.com",
        "twistys.com", "fakehub.com", "letsdoeit.com", "puretaboo.com", "adulttime.com",
        "nubiles.net", "nubilefilms.com", "familystrokes.com", "manyvids.com", "clips4sale.com",
        "iwantclips.com", "pornpros.com", "girlsway.com", "ddfnetwork.com", "wowgirls.com",
        "joymii.com", "sexart.com", "vivid.com", "wicked.com", "elegantangel.com",
        // Cams and creator platforms
        "livejasmin.com", "bongacams.com", "cam4.com", "camsoda.com", "myfreecams.com",
        "flirt4free.com", "streamate.com", "imlive.com", "jerkmate.com", "xlovecam.com",
        "cams.com", "camster.com", "slutroulette.com", "fansly.com", "fanvue.com",
        "justfor.fans", "loyalfans.com", "fancentro.com", "admireme.vip", "4based.com",
        "stripchat.global", "chaturbate.global", "sakuralive.com", "camwhores.tv",
        "camwhoresbay.com", "recurbate.com", "camvideos.tv", "xcams.com",
        // Image boards, galleries, leaks, drawn content
        "rule34.xxx", "rule34.paheal.net", "e621.net", "gelbooru.com", "danbooru.donmai.us",
        "sankakucomplex.com", "hentaihaven.xxx", "hanime.tv", "e-hentai.org", "exhentai.org",
        "hentai2read.com", "hitomi.la", "pururin.to", "tsumino.com", "imagefap.com",
        "pornpics.com", "pichunter.com", "sex.com", "erome.com", "thothub.to", "thothub.tv",
        "fapello.com", "fapopedia.net", "coomer.su", "coomer.party", "kemono.su",
        "kemono.party", "simpcity.su", "leakedmodels.com", "nudostar.com", "influencersgonewild.com",
        "scrolller.com", "porngifs.com", "gifsauce.com", "sexygirlspics.com", "hotgirlclub.com",
        "nsfwalbum.com", "nudogram.com", "celebjihad.com", "ancensored.com", "mrskin.com",
        "f95zone.to", "nutaku.net", "lewdzone.com", "8muses.com", "multporn.net",
        // Directories, review sites and adult search
        "pornmd.com", "porngeek.com", "thepornlist.net", "thebestfetishsites.com",
        "pornwhitelist.com", "mypornbible.com", "tubepornclassic.com", "xxxsearch.com",
        "porndude.com", "pornsites.xxx", "pornmate.com", "toppornsites.com",
        "nichepornsites.com", "pornkai.com", "adultdvdempire.com", "iafd.com", "freeones.com",
        "babepedia.com", "boobpedia.com", "data18.com", "indexxx.com",
        // Erotic stories and audio
        "literotica.com", "asstr.org", "sexstories.com", "lushstories.com", "gonewildaudio.com",
        "quinn.app", "dipseastories.com",
        // Escort and hookup
        "adultfriendfinder.com", "ashleymadison.com", "fling.com", "benaughty.com",
        "slixa.com", "eros.com", "tryst.link", "skipthegames.com", "listcrawler.eu",
        "megapersonals.eu", "doublelist.com",
    ]
}
