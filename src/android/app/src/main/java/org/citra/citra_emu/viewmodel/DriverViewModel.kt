// Copyright 2023-2026 Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the misc/licenses/gplv2.txt file included.

package org.citra.citra_emu.viewmodel

import android.net.Uri
import android.widget.Toast
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.citra.citra_emu.CitraApplication
import org.citra.citra_emu.R
import org.citra.citra_emu.utils.FileUtil.asDocumentFile
import org.citra.citra_emu.utils.GpuDriverHelper
import org.citra.citra_emu.utils.GpuDriverMetadata
import org.citra.citra_emu.utils.Log

class DriverViewModel : ViewModel() {
    val areDriversLoading get() = _areDriversLoading.asStateFlow()
    private val _areDriversLoading = MutableStateFlow(false)

    val isDriverReady get() = _isDriverReady.asStateFlow()
    private val _isDriverReady = MutableStateFlow(true)

    val isDeletingDrivers get() = _isDeletingDrivers.asStateFlow()
    private val _isDeletingDrivers = MutableStateFlow(false)

    val driverList get() = _driverList.asStateFlow()
    private val _driverList = MutableStateFlow(mutableListOf<Pair<Uri, GpuDriverMetadata>>())

    var previouslySelectedDriver = 0
    var selectedDriver = -1

    private val _selectedDriverMetadata =
        MutableStateFlow(
            GpuDriverHelper.customDriverData.name
                ?: CitraApplication.appContext.getString(R.string.system_gpu_driver)
        )
    val selectedDriverMetadata: StateFlow<String> get() = _selectedDriverMetadata

    private val _newDriverInstalled = MutableStateFlow(false)
    val newDriverInstalled: StateFlow<Boolean> get() = _newDriverInstalled

    val driversToDelete = mutableListOf<Uri>()

    val isInteractionAllowed
        get() = !areDriversLoading.value && isDriverReady.value && !isDeletingDrivers.value

    init {
        _areDriversLoading.value = true
        viewModelScope.launch {
            withContext(Dispatchers.IO) {
                val drivers = GpuDriverHelper.getDrivers()
                val currentDriverMetadata = GpuDriverHelper.customDriverData
                for (i in drivers.indices) {
                    if (drivers[i].second == currentDriverMetadata) {
                        setSelectedDriverIndex(i)
                        break
                    }
                }

                _driverList.value = drivers
                _areDriversLoading.value = false
            }
        }
    }

    fun setSelectedDriverIndex(value: Int) {
        if (selectedDriver != -1) {
            previouslySelectedDriver = selectedDriver
        }
        selectedDriver = value
    }

    fun setNewDriverInstalled(value: Boolean) {
        _newDriverInstalled.value = value
    }

    fun addDriver(driverData: Pair<Uri, GpuDriverMetadata>) {
        val driverIndex = _driverList.value.indexOfFirst { it == driverData }
        if (driverIndex == -1) {
            setSelectedDriverIndex(_driverList.value.size)
            _driverList.value.add(driverData)
            _selectedDriverMetadata.value = driverData.second.name
                ?: CitraApplication.appContext.getString(R.string.system_gpu_driver)
        } else {
            setSelectedDriverIndex(driverIndex)
        }
    }

    fun removeDriver(driverData: Pair<Uri, GpuDriverMetadata>) {
        _driverList.value.remove(driverData)
    }

    fun onCloseDriverManager() {
        _isDeletingDrivers.value = true
        viewModelScope.launch {
            withContext(Dispatchers.IO) {
                for (driverUri in driversToDelete) {
                    val driver = driverUri.asDocumentFile() ?: continue
                    if (driver.exists()) {
                        driver.delete()
                    }
                }
                driversToDelete.clear()
                _isDeletingDrivers.value = false
            }
        }

        val selected = driverList.value.getOrNull(selectedDriver) ?: return
        if (GpuDriverHelper.customDriverData == selected.second) {
            return
        }

        _isDriverReady.value = false
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    if (selectedDriver == 0) {
                        GpuDriverHelper.installDefaultDriver()
                        return@withContext
                    }

                    val driverToInstall = selected.first.asDocumentFile()
                    if (driverToInstall == null || !driverToInstall.exists()) {
                        GpuDriverHelper.installDefaultDriver()
                        return@withContext
                    }

                    // A package that fails to unpack leaves the driver in use as it was.
                    GpuDriverHelper.installCustomDriverPartial(driverToInstall.uri)
                }
            } catch (e: Exception) {
                Log.error("[DriverViewModel] Failed to switch driver: ${e.message}")
            } finally {
                // Always release the loading dialog, whatever the outcome.
                setDriverReady()
            }

            // The native driver is loaded once per process; the new one applies on the next start.
            if (GpuDriverHelper.restartRequired) {
                Toast.makeText(
                    CitraApplication.appContext,
                    R.string.gpu_driver_restart_required,
                    Toast.LENGTH_LONG
                ).show()
            }
        }
    }

    private fun setDriverReady() {
        _isDriverReady.value = true
        _selectedDriverMetadata.value = GpuDriverHelper.customDriverData.name
            ?: CitraApplication.appContext.getString(R.string.system_gpu_driver)
    }
}
