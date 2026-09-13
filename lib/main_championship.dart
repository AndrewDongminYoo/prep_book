import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:prep_book/championship/championship.dart';
import 'package:prep_book/presentation/production_sheet/view/production_sheet_launcher.dart';
import 'package:prep_book/presentation/production_sheet/view/production_sheet_platform.dart';

void main() {
  runApp(const _ChampionshipRoot());
}

class _ChampionshipRoot extends StatefulWidget {
  const _ChampionshipRoot();

  @override
  State<_ChampionshipRoot> createState() => _ChampionshipRootState();
}

class _ChampionshipRootState extends State<_ChampionshipRoot> {
  late final http.Client _httpClient;
  late final ChampionshipDemoCubit _cubit;
  final _productionSheet = const ProductionSheetLauncher(
    platform: PrintingProductionSheetPlatform(),
  );

  @override
  void initState() {
    super.initState();
    _httpClient = http.Client();
    const endpointValue = String.fromEnvironment(
      'AI_IMPORT_ENDPOINT',
      defaultValue: '/api/extract-recipe',
    );
    final parsedEndpoint = Uri.parse(endpointValue);
    final endpoint = parsedEndpoint.hasScheme
        ? parsedEndpoint
        : Uri.base.resolveUri(parsedEndpoint);
    _cubit = ChampionshipDemoCubit(
      importClient: HttpRecipeImportClient(
        client: _httpClient,
        endpoint: endpoint,
      ),
      imagePicker: const FilePickerRecipeImagePicker(),
      sampleLoader: ChampionshipSampleLoader(bundle: rootBundle),
    );
  }

  @override
  void dispose() {
    unawaited(_cubit.close());
    _httpClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChampionshipApp(
    cubit: _cubit,
    openProductionSheet: (context, run) =>
        _productionSheet.open(context, run: run),
  );
}
