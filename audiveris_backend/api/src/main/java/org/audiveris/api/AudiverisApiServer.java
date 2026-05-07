package org.audiveris.api;

import io.javalin.Javalin;
import io.javalin.http.UploadedFile;

import org.audiveris.omr.CLI;
import org.audiveris.omr.Main;
import org.audiveris.omr.OMR;
import org.audiveris.omr.WellKnowns;
import org.audiveris.omr.sheet.Book;
import org.audiveris.omr.sheet.BookManager;
import org.audiveris.omr.sheet.SheetStub;
import org.audiveris.omr.score.Score;
import org.audiveris.omr.text.tesseract.Languages;
import org.audiveris.omr.ui.symbol.MusicFont;
import org.audiveris.omr.util.OmrExecutors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;

/**
 * Javalin HTTP server that exposes Audiveris OMR as a REST API.
 *
 * Endpoints:
 *   GET  /health      — liveness check + version
 *   POST /transcribe  — multipart field "file" (image or PDF) → MusicXML (.mxl)
 *
 * Set PORT env var to override the default port (7000).
 * Transcription requests are serialized; Audiveris is CPU-bound and not thread-safe across jobs.
 */
public class AudiverisApiServer
{
    private static final Logger logger = LoggerFactory.getLogger(AudiverisApiServer.class);

    /** Serializes access to the Audiveris engine and the static Main.cli field. */
    private static final Object ENGINE_LOCK = new Object();

    public static void main (String[] args) throws Exception
    {
        System.setProperty("java.awt.headless", "true");
        initAudiveris();

        int port = Integer.parseInt(System.getenv().getOrDefault("PORT", "7000"));

        Javalin app = Javalin.create(cfg -> cfg.http.maxRequestSize = 100_000_000L)

            .get("/health", ctx -> ctx.json(Map.of(
                "status", "ok",
                "version", WellKnowns.TOOL_REF
            )))

            .post("/transcribe", ctx -> {
                UploadedFile upload = ctx.uploadedFile("file");
                if (upload == null) {
                    ctx.status(400).json(Map.of(
                        "error", "Missing multipart field 'file'."
                    ));
                    return;
                }

                // Sanitize filename to prevent path traversal
                String filename = Path.of(upload.filename()).getFileName().toString();

                Path tempDir = Files.createTempDirectory("audiveris-");
                try {
                    Path inputPath = tempDir.resolve(filename);
                    try (var stream = upload.content()) {
                        Files.copy(stream, inputPath, StandardCopyOption.REPLACE_EXISTING);
                    }

                    Path result = transcribe(inputPath, tempDir);

                    if (result == null) {
                        ctx.status(422).json(Map.of(
                            "error", "Transcription produced no MusicXML output."
                        ));
                        return;
                    }

                    String outName = result.getFileName().toString();
                    ctx.contentType(outName.endsWith(".mxl")
                        ? "application/vnd.recordare.musicxml"
                        : "application/xml");
                    ctx.header("Content-Disposition", "attachment; filename=\"" + outName + "\"");
                    // Read before finally-block deletes tempDir
                    ctx.result(Files.readAllBytes(result));

                } finally {
                    deleteDir(tempDir);
                }
            })

            .start(port);

        logger.info("Audiveris REST API running on :{}", port);

        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            app.stop();
            OmrExecutors.shutdown();
        }));
    }

    //~ Private helpers ----------------------------------------------------------------------------

    /**
     * Runs the full OMR pipeline on {@code inputPath}, writing all output into {@code outputDir},
     * then returns the path to the first exported MusicXML file found there.
     */
    private static Path transcribe (Path inputPath, Path outputDir) throws Exception
    {
        String filename = inputPath.getFileName().toString();
        String stem = filename.contains(".")
            ? filename.substring(0, filename.lastIndexOf('.'))
            : filename;

        synchronized (ENGINE_LOCK) {
            // Point the shared CLI at this request's temp directory so that all
            // Audiveris output (book save, export) lands there and is easy to clean up.
            setCliOutputFolder(outputDir);

            Book book = OMR.engine.loadInput(inputPath);
            if (book == null) {
                throw new RuntimeException("Could not open input file: " + filename);
            }

            try {
                // Direct the MusicXML export to outputDir/<stem>.mxl
                book.setExportPathSansExt(outputDir.resolve(stem));

                // Create stubs (pages) if the book is fresh, and persist the initial book file
                // so that the swap mechanism can write sheet data to it during processing.
                if (book.getStubs().isEmpty()) {
                    book.createStubs();
                    book.store(BookManager.getDefaultSavePath(book), false);
                }

                List<SheetStub> stubs = Book.getValidStubs(book.getStubs());
                if (stubs.isEmpty()) {
                    throw new RuntimeException("No processable sheets found in: " + filename);
                }

                List<Score> scores = book.getScores();

                // export() runs transcription then writes MusicXML
                if (!book.export(stubs, scores)) {
                    throw new RuntimeException("OMR export failed for: " + filename);
                }

            } finally {
                book.close(null);
            }
        }

        // Find the exported .mxl or .xml file (exclude the input file itself)
        try (Stream<Path> files = Files.list(outputDir)) {
            return files
                .filter(p -> {
                    String n = p.getFileName().toString();
                    return !n.equals(filename) && (n.endsWith(".mxl") || n.endsWith(".xml"));
                })
                .findFirst()
                .orElse(null);
        }
    }

    /**
     * Re-parses a minimal batch CLI pointing the output folder at {@code folder}.
     * Must be called inside ENGINE_LOCK to avoid concurrent mutation of Main.cli.
     */
    private static void setCliOutputFolder (Path folder) throws Exception
    {
        CLI cli = new CLI(WellKnowns.TOOL_NAME);
        cli.parseParameters("-batch", "-output", folder.toString());
        Field f = Main.class.getDeclaredField("cli");
        f.setAccessible(true);
        f.set(null, cli);
    }

    /**
     * One-time Audiveris engine initialisation (mirrors the batch path in Main.main).
     */
    private static void initAudiveris () throws Exception
    {
        // Install a no-op batch CLI so Main.getCli() is never null during startup checks
        CLI cli = new CLI(WellKnowns.TOOL_NAME);
        cli.parseParameters("-batch");
        Field f = Main.class.getDeclaredField("cli");
        f.setAccessible(true);
        f.set(null, cli);

        OmrExecutors.restart();
        OMR.engine = BookManager.getInstance();
        Languages.getInstance().checkSupport();
        MusicFont.checkMusicFont();
    }

    private static void deleteDir (Path dir)
    {
        try (Stream<Path> files = Files.walk(dir)) {
            files.sorted((a, b) -> b.compareTo(a))
                .forEach(p -> {
                    try {
                        Files.deleteIfExists(p);
                    } catch (IOException ignored) {}
                });
        } catch (IOException ignored) {}
    }
}
