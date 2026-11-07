// Copyright 2023-2026 Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the misc/licenses/gplv2.txt file included.

package org.citra.citra_emu.utils

import android.net.Uri
import android.os.Build
import androidx.documentfile.provider.DocumentFile
import java.io.BufferedInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.lang.IllegalStateException
import java.util.zip.ZipEntry
import java.util.zip.ZipException
import java.util.zip.ZipInputStream
import org.citra.citra_emu.CitraApplication
import org.citra.citra_emu.NativeLibrary
import org.citra.citra_emu.utils.FileUtil.inputStream

object GpuDriverHelper {
    private const val META_JSON_FILENAME = "meta.json"
    private var fileRedirectionPath: String? = null
    var driverInstallationPath: String? = null
    private var hookLibPath: String? = null

    /**
     * The native Vulkan loader (adrenotools) is only ever run once per process, like hakuX, which
     * loads its driver at game start and never while the app is switching packages. Reloading a
     * driver in a live process (the old library is still mapped, its hooks still patched in) is
     * what crashed games when a Turnip package was imported. A change made after the first load
     * is applied the next time the app starts; [restartRequired] tells the UI so.
     */
    @Volatile
    private var nativeDriverLoaded = false

    @Volatile
    var restartRequired = false
        private set

    val driverStoragePath: DocumentFile
        get() {
            // Bypass directory initialization checks
            val root = DocumentFile.fromTreeUri(
                CitraApplication.appContext,
                Uri.parse(DirectoryInitialization.userPath)
            )!!
            var driverDirectory = root.findFile("gpu_drivers")
            if (driverDirectory == null) {
                driverDirectory = FileUtil.createDir(root.uri.toString(), "gpu_drivers")
            }
            return driverDirectory!!
        }

    fun initializeDriverParameters() {
        try {
            // Initialize the file redirection directory.
            fileRedirectionPath =
                DirectoryInitialization.internalUserPath + "/gpu/vk_file_redirect/"

            // Initialize the driver installation directory.
            driverInstallationPath = CitraApplication.appContext
                .filesDir.canonicalPath + "/gpu_driver/"
        } catch (e: IOException) {
            throw RuntimeException(e)
        }

        // Initialize directories.
        initializeDirectories()

        // Initialize hook libraries directory.
        hookLibPath = CitraApplication.appContext.applicationInfo.nativeLibraryDir + "/"

        // Never reload the driver in a live process: the change applies on the next start.
        if (nativeDriverLoaded) {
            restartRequired = true
            return
        }
        nativeDriverLoaded = true

        // Only hand the native side a library that is really there; a half-installed package
        // (meta.json without its library) must fall back to the system driver, not crash.
        val libraryName = customDriverData.libraryName
            ?.takeIf { it.isNotEmpty() && File(driverInstallationPath + it).isFile }

        // Initialize GPU driver.
        NativeLibrary.initializeGpuDriver(
            hookLibPath,
            driverInstallationPath,
            libraryName,
            fileRedirectionPath
        )
    }

    fun getDrivers(): MutableList<Pair<Uri, GpuDriverMetadata>> {
        val driverZips = driverStoragePath.listFiles()
        val drivers: MutableList<Pair<Uri, GpuDriverMetadata>> =
            driverZips
                .filter { it.isFile }
                .mapNotNull {
                    val metadata = getMetadataFromZip(it.inputStream())
                    metadata.name?.let { _ -> Pair(it.uri, metadata) }
                }
                .sortedByDescending { it: Pair<Uri, GpuDriverMetadata> -> it.second.name }
                .distinct()
                .toMutableList()

        // TODO: Get system driver information
        drivers.add(0, Pair(Uri.EMPTY, GpuDriverMetadata()))
        return drivers
    }

    fun installDefaultDriver() {
        // Removing the installed driver will result in the backend using the default system driver.
        File(driverInstallationPath!!).deleteRecursively()
        File(driverInstallationPath!!).mkdirs()
        initializeDriverParameters()
    }

    fun copyDriverToExternalStorage(driverUri: Uri): DocumentFile? {
        return try {
            // Ensure we have directories.
            initializeDirectories()

            // Check the package where it is, before anything is stored: a bad zip leaves no trace.
            val metadata = driverUri.inputStream().use { getMetadataFromZip(it) }
            if (!isUsable(metadata) || !zipHasEntry(driverUri.inputStream(), metadata.libraryName!!)) {
                return null
            }

            // Copy the zip file URI to user data
            FileUtil.copyToExternalStorage(driverUri, driverStoragePath)
        } catch (e: Exception) {
            Log.error("[GpuDriverHelper] Failed to import driver: ${e.message}")
            null
        }
    }

    /** A package that names itself and the library to load, and fits this Android version. */
    private fun isUsable(metadata: GpuDriverMetadata): Boolean =
        metadata.name != null &&
            !metadata.libraryName.isNullOrEmpty() &&
            metadata.minApi <= Build.VERSION.SDK_INT

    private fun zipHasEntry(zipStream: InputStream, entryName: String): Boolean =
        try {
            ZipInputStream(BufferedInputStream(zipStream)).use { zis ->
                var entry: ZipEntry? = zis.nextEntry
                while (entry != null) {
                    if (!entry.isDirectory && entry.name == entryName) return true
                    entry = zis.nextEntry
                }
                false
            }
        } catch (_: IOException) {
            false
        }

    /**
     * Unpacks a driver beside the one in use and swaps it in only once it is whole (as hakuX
     * does): a package that fails to unpack, or lacks its library, leaves the driver as it was.
     */
    private fun unpackDriver(openZip: () -> InputStream, metadata: GpuDriverMetadata): Boolean {
        val installDir = File(driverInstallationPath!!)
        val newDir = File(installDir.parentFile, installDir.name + ".new")
        newDir.deleteRecursively()
        newDir.mkdirs()
        try {
            FileUtil.unzipToInternalStorage(BufferedInputStream(openZip()), newDir)
            if (!File(newDir, metadata.libraryName!!).isFile) {
                throw IOException("Driver package lacks ${metadata.libraryName}")
            }
        } catch (e: Exception) {
            Log.error("[GpuDriverHelper] Failed to unpack driver: ${e.message}")
            newDir.deleteRecursively()
            return false
        }
        installDir.deleteRecursively()
        if (!newDir.renameTo(installDir)) {
            Log.error("[GpuDriverHelper] Failed to move the driver into place")
            newDir.deleteRecursively()
            installDir.mkdirs()
            return false
        }
        return true
    }

    /**
     * Copies driver zip into user data directory so that it can be exported along with
     * other user data and also unzipped into the installation directory
     */
    fun installCustomDriverComplete(driverUri: Uri): Boolean {
        val copiedFile = copyDriverToExternalStorage(driverUri) ?: return false
        return installCustomDriverPartial(copiedFile.uri)
    }

    /**
     * Unzips driver into private installation directory
     */
    fun installCustomDriverPartial(driver: Uri): Boolean {
        return try {
            // Ensure we have directories.
            initializeDirectories()

            // Validate driver
            val metadata = driver.inputStream().use { getMetadataFromZip(it) }
            if (!isUsable(metadata)) {
                return false
            }

            // Unzip beside the driver in use, swapping it in only if the package is whole.
            if (!unpackDriver({ driver.inputStream() }, metadata)) {
                return false
            }

            // Initialize the driver parameters (the native load itself happens once per process).
            initializeDriverParameters()
            true
        } catch (e: Exception) {
            Log.error("[GpuDriverHelper] Failed to install driver: ${e.message}")
            false
        }
    }

    /**
     * Takes in a zip file and reads the meta.json file for presentation to the UI
     *
     * @param driver Zip containing driver and meta.json file
     * @return A non-null [GpuDriverMetadata] instance that may have null members
     */
    fun getMetadataFromZip(driver: InputStream): GpuDriverMetadata {
        try {
            ZipInputStream(driver).use { zis ->
                var entry: ZipEntry? = zis.nextEntry
                while (entry != null) {
                    if (!entry.isDirectory && entry.name.lowercase().contains(".json")) {
                        val size = if (entry.size == -1L) 0L else entry.size
                        return GpuDriverMetadata(zis, size)
                    }
                    entry = zis.nextEntry
                }
            }
        } catch (_: ZipException) {
        }
        return GpuDriverMetadata()
    }

    external fun supportsCustomDriverLoading(): Boolean

    // Parse the custom driver metadata to retrieve the name.
    val customDriverData: GpuDriverMetadata
        get() = GpuDriverMetadata(File(driverInstallationPath + META_JSON_FILENAME))

    fun initializeDirectories() {
        // Ensure the file redirection directory exists.
        val fileRedirectionDir = File(fileRedirectionPath!!)
        if (!fileRedirectionDir.exists()) {
            fileRedirectionDir.mkdirs()
        }
        // Ensure the driver installation directory exists.
        val driverInstallationDir = File(driverInstallationPath!!)
        if (!driverInstallationDir.exists()) {
            driverInstallationDir.mkdirs()
        }
        // Ensure the driver storage directory exists
        if (!driverStoragePath.exists()) {
            throw IllegalStateException("Driver storage directory couldn't be created!")
        }
    }
}
