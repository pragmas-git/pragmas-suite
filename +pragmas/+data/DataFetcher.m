classdef DataFetcher < handle
    % DATAFETCHER Clase para fetch asincrónico de datos financieros.
    
    properties
        Symbols         % Cell array de símbolos (e.g., {'EURUSD=X', 'BTC-USD'})
        StartDate       % datetime
        EndDate         % datetime
        Source          % 'yahoo' o 'crypto'
        DataTables      % Cell array de timetables fetchados
    end
    
    methods
        function obj = DataFetcher(symbols, startDate, endDate, source)
            obj.Symbols = cellstr(symbols);
            obj.StartDate = startDate;
            obj.EndDate = endDate;
            if nargin < 4
                obj.Source = 'yahoo';
            else
                obj.Source = source;
            end
            obj.DataTables = cell(size(obj.Symbols));
        end
        
        function fetchAsync(obj)
            % FETCHASYNC Descarga datos en paralelo usando parfeval.
            global PRAGMAS_PARPOOL_SIZE;
            
            p = gcp('nocreate');  % Obtiene pool paralelo (inicia si no existe)
            if isempty(p)
                if ~isempty(PRAGMAS_PARPOOL_SIZE)
                    parpool(PRAGMAS_PARPOOL_SIZE);
                else
                    parpool(4);  % Default
                end
            end
            
            futures = cell(size(obj.Symbols));
            for i = 1:length(obj.Symbols)
                futures{i} = parfeval(@obj.fetchSingle, 1, obj.Symbols{i});
            end
            
            % Espera y recolecta
            for i = 1:length(futures)
                [idx, dataTable] = fetchNext(futures);
                obj.DataTables{idx} = dataTable;
            end
        end
        
        function dataTable = fetchSingle(obj, symbol)
            % FETCHSINGLE Función helper para fetch individual (compatible con parfeval).
            global PRAGMAS_DATA_SOURCES;
            
            try
                if strcmp(obj.Source, 'yahoo')
                    % Intenta usar Financial Toolbox si disponible
                    try
                        conn = yahoo;
                        dataTable = fetch(conn, symbol, obj.StartDate, obj.EndDate);
                        close(conn);
                    catch
                        % Fallback: webread simple (requiere procesamiento manual)
                        warning('Financial Toolbox no disponible. Usando fallback webread.');
                        dataTable = obj.fetchYahooWebread(symbol);
                    end
                    
                elseif strcmp(obj.Source, 'crypto')
                    % CoinGecko API
                    dataTable = obj.fetchCryptoCoingecko(symbol);
                    
                else
                    error('Fuente "%s" no soportada.', obj.Source);
                end
                
                % Limpieza: remover NaNs, outliers
                dataTable = rmmissing(dataTable);
                if height(dataTable) > 5
                    dataTable.Close = filloutliers(dataTable.Close, 'linear', 'movmedian', 5);
                end
                
            catch ME
                warning('Error fetcheando %s: %s', symbol, ME.message);
                dataTable = table();
            end
        end
        
        function dataTable = fetchYahooWebread(obj, symbol)
            % FETCHYAHOOWEBREAD Descarga Yahoo Finance vía webread (fallback).
            % Nota: Yahoo ha cambiado frecuentemente su API; este es un ejemplo básico.
            try
                url = sprintf('https://query1.finance.yahoo.com/v8/finance/chart/%s?interval=1d&events=history', symbol);
                options = weboptions('Timeout', 10, 'ContentType', 'json');
                response = webread(url, options);
                
                % Procesa respuesta JSON
                chart = response.chart.result{1};
                timestamps = chart.timestamp;
                quotes = chart.indicators.quote{1};
                
                dates = datetime(timestamps, 'ConvertFrom', 'posixtime', 'TimeZone', 'UTC');
                closes = quotes.close';
                
                dataTable = timetable(dates, closes, 'VariableNames', {'Close'});
                
            catch
                % Fallback: retorna timetable vacío si falla
                dataTable = timetable.empty();
            end
        end
        
        function dataTable = fetchCryptoCoingecko(obj, symbol)
            % FETCHCRYPTOCOINGECKO Descarga datos criptográficos vía CoinGecko API.
            global PRAGMAS_DATA_SOURCES;
            
            % Mapeo común de símbolos a IDs CoinGecko
            symbolMap = containers.Map(...
                {'BTC', 'BTC-USD', 'ETH', 'ETH-USD', 'ADA', 'ADA-USD', 'SOL', 'SOL-USD'}, ...
                {'bitcoin', 'bitcoin', 'ethereum', 'ethereum', 'cardano', 'cardano', 'solana', 'solana'});
            
            if isKey(symbolMap, symbol)
                coinId = symbolMap(symbol);
            else
                coinId = lower(symbol);  % Asume ID == símbolo en minúsculas
            end
            
            try
                fromTime = posixtime(obj.StartDate);
                toTime = posixtime(obj.EndDate);
                
                url = sprintf('%s/coins/%s/market_chart/range?vs_currency=usd&from=%d&to=%d', ...
                    PRAGMAS_DATA_SOURCES.crypto, coinId, int64(fromTime), int64(toTime));
                
                options = weboptions('Timeout', 10, 'ContentType', 'json');
                response = webread(url, options);
                
                prices = response.prices;  % [[timestamp, price], ...]
                if isempty(prices)
                    error('No data returned for %s', symbol);
                end
                
                timestamps = cell2mat(prices(:, 1)) / 1000;  % Convertir msec a sec
                closes = cell2mat(prices(:, 2));
                
                dates = datetime(timestamps, 'ConvertFrom', 'posixtime', 'TimeZone', 'UTC');
                dataTable = timetable(dates, closes, 'VariableNames', {'Close'});
                
            catch ME
                warning('Error en CoinGecko para %s: %s', symbol, ME.message);
                dataTable = timetable.empty();
            end
        end
    end
end
